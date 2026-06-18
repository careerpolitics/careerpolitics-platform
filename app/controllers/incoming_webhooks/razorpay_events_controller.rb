module IncomingWebhooks
  class RazorpayEventsController < ApplicationController
    skip_before_action :verify_authenticity_token

    def self.webhook_secret
      Settings::General.razorpay_webhook_secret
    end

    def create
      payload = request.body.read
      signature = request.headers["X-Razorpay-Signature"]

      unless verify_signature(payload, signature)
        Rails.logger.error "Razorpay webhook signature verification failed"
        render json: { error: "Invalid signature" }, status: :bad_request and return
      end

      event = JSON.parse(payload)
      event_type = event["event"]

      Rails.logger.info "Razorpay webhook event: #{event_type}"

      case event_type
      when "subscription.activated"
        handle_subscription_activated(event["payload"]["subscription"]["entity"])
      when "subscription.charged"
        handle_subscription_charged(event["payload"]["subscription"]["entity"],
                                    event["payload"]["payment"]["entity"])
      when "subscription.completed"
        handle_subscription_completed(event["payload"]["subscription"]["entity"])
      when "subscription.cancelled"
        handle_subscription_cancelled(event["payload"]["subscription"]["entity"])
      when "subscription.halted"
        handle_subscription_halted(event["payload"]["subscription"]["entity"])
      when "payment.captured"
        handle_payment_captured(event["payload"]["payment"]["entity"])
      else
        Rails.logger.info "Unhandled Razorpay event type: #{event_type}"
      end

      render json: { status: "success" }, status: :ok
    rescue JSON::ParserError => e
      Rails.logger.error "Razorpay webhook JSON parse error: #{e.message}"
      render json: { error: "Invalid payload" }, status: :bad_request
    end

    private

    def verify_signature(payload, signature)
      secret = self.class.webhook_secret
      return false if signature.blank? || secret.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def handle_subscription_activated(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      unless user.base_subscriber?
        user.add_role("base_subscriber")
        user.update(
          razorpay_subscription_id: subscription["id"],
          current_subscriber_status: :paying_subscription,
          )
        user.profile&.touch
        NotifyMailer.with(user: user).base_subscriber_role_email.deliver_later
      end

      # Ensure a CpSubscription record exists
      ensure_cp_subscription(user, subscription)
    end

    def handle_subscription_charged(subscription, payment)
      user = find_user_from_notes(subscription)
      return unless user

      user.add_role("base_subscriber") unless user.base_subscriber?
      user.update(current_subscriber_status: :paying_subscription)

      # Persist the payment record
      cp_sub = ensure_cp_subscription(user, subscription)
      record_payment(cp_sub, user, payment) if cp_sub

      # Update period dates from Razorpay
      if subscription["current_start"] && subscription["current_end"]
        cp_sub&.update(
          current_period_start: Time.zone.at(subscription["current_start"]),
          current_period_end: Time.zone.at(subscription["current_end"]),
          )
      end

      Rails.logger.info "Razorpay subscription charged for user #{user.id}, payment: #{payment['id']}"
    end

    def handle_subscription_completed(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      cp_sub = user.cp_subscriptions.find_by(razorpay_subscription_id: subscription["id"])
      cp_sub&.update(status: :expired, cancelled_at: Time.current)

      Rails.logger.info "Razorpay subscription completed for user #{user.id}"
    end

    def handle_subscription_cancelled(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      cp_sub = user.cp_subscriptions.find_by(razorpay_subscription_id: subscription["id"])
      cp_sub&.update(status: :cancelled, cancelled_at: Time.current)

      user.remove_role("base_subscriber")
      user.update(current_subscriber_status: :not_subscribed)
      user.touch
      user.profile&.touch
      Rails.logger.info "Razorpay subscription cancelled for user #{user.id}"
    end

    def handle_subscription_halted(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      cp_sub = user.cp_subscriptions.find_by(razorpay_subscription_id: subscription["id"])
      cp_sub&.update(status: :halted)

      # Grace period: warn the user but don't immediately revoke access
      Rails.logger.warn "Razorpay subscription halted (payment failures) for user #{user.id}"
      # Schedule access revocation after grace period (3 days)
      Subscriptions::RevokeHaltedAccessWorker.perform_in(3.days.to_i, user.id, cp_sub&.id)
    end

    def handle_payment_captured(payment)
      Rails.logger.info "Razorpay payment captured: #{payment['id']}, amount: #{payment['amount']}"
    end

    def ensure_cp_subscription(user, subscription)
      user.cp_subscriptions.find_or_create_by!(razorpay_subscription_id: subscription["id"]) do |cs|
        cs.razorpay_plan_id = subscription["plan_id"]
        cs.status = :active
        cs.provider = "razorpay"
        cs.current_period_start = subscription["current_start"] ? Time.zone.at(subscription["current_start"]) : Time.current
        cs.current_period_end = subscription["current_end"] ? Time.zone.at(subscription["current_end"]) : nil
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to ensure CpSubscription for user #{user.id}: #{e.message}"
      nil
    end

    def record_payment(cp_sub, user, payment)
      return if CpPayment.exists?(razorpay_payment_id: payment["id"])

      cp_sub.cp_payments.create!(
        user: user,
        razorpay_payment_id: payment["id"],
        amount_cents: payment["amount"] || 0,
        currency: (payment["currency"] || "INR").upcase,
        method_type: payment["method"],
        status: :captured,
        paid_at: payment["created_at"] ? Time.zone.at(payment["created_at"]) : Time.current,
        )

      NotifyMailer.with(user: user).base_subscriber_role_email.deliver_later
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to record payment #{payment['id']} for user #{user.id}: #{e.message}"
    end

    def find_user_from_notes(entity)
      notes = entity["notes"] || {}
      user_id = notes["user_id"]

      unless user_id
        Rails.logger.warn "Razorpay webhook: no user_id in notes for entity #{entity['id']}"
        return nil
      end

      user = User.find_by(id: user_id)
      Rails.logger.warn "Razorpay webhook: user not found for id #{user_id}" unless user
      user
    end
  end
end
