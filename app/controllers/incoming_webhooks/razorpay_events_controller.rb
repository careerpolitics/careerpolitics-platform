module IncomingWebhooks
  class RazorpayEventsController < ApplicationController
    skip_before_action :verify_authenticity_token

    RAZORPAY_WEBHOOK_SECRET = ApplicationConfig["RAZORPAY_WEBHOOK_SECRET"]

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
      return false if signature.blank? || RAZORPAY_WEBHOOK_SECRET.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", RAZORPAY_WEBHOOK_SECRET, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def handle_subscription_activated(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      unless user.base_subscriber?
        user.add_role("base_subscriber")
        user.update(
          stripe_id_code: subscription["id"],
          current_subscriber_status: :paying_subscription,
          )
        user.profile&.touch
        NotifyMailer.with(user: user).base_subscriber_role_email.deliver_later
      end
    end

    def handle_subscription_charged(subscription, payment)
      user = find_user_from_notes(subscription)
      return unless user

      user.add_role("base_subscriber") unless user.base_subscriber?
      user.update(current_subscriber_status: :paying_subscription)
      Rails.logger.info "Razorpay subscription charged for user #{user.id}, payment: #{payment['id']}"
    end

    def handle_subscription_completed(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      Rails.logger.info "Razorpay subscription completed for user #{user.id}"
    end

    def handle_subscription_cancelled(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      user.remove_role("base_subscriber")
      user.update(current_subscriber_status: :not_subscribed)
      user.touch
      user.profile&.touch
      Rails.logger.info "Razorpay subscription cancelled for user #{user.id}"
    end

    def handle_subscription_halted(subscription)
      user = find_user_from_notes(subscription)
      return unless user

      user.remove_role("base_subscriber")
      user.update(current_subscriber_status: :not_subscribed)
      Rails.logger.warn "Razorpay subscription halted (payment failures) for user #{user.id}"
    end

    def handle_payment_captured(payment)
      Rails.logger.info "Razorpay payment captured: #{payment['id']}, amount: #{payment['amount']}"
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
