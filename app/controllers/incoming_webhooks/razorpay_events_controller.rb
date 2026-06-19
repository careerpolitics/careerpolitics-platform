module IncomingWebhooks
  class RazorpayEventsController < ApplicationController
    skip_before_action :verify_authenticity_token

    def self.webhook_secret
      Settings::General.razorpay_webhook_secret
    end

    def create
      payload = request.body.read
      signature = request.headers["X-Razorpay-Signature"]

      unless signature.present? && verify_signature(payload, signature)
        head :bad_request and return
      end

      event = JSON.parse(payload)
      event_type = event["event"]

      Rails.logger.info "Razorpay webhook event: #{event_type}"

      case event_type
      when "payment.captured"
        handle_payment_captured(event["payload"]["payment"]["entity"])
      else
        Rails.logger.info "Unhandled Razorpay event type: #{event_type}"
      end

      head :ok
    end

    private

    def verify_signature(payload, signature)
      secret = self.class.webhook_secret
      return false if secret.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def handle_payment_captured(payment)
      Rails.logger.info "Razorpay payment captured: #{payment['id']}, amount: #{payment['amount']}"

      return unless payment["id"].present?

      cp_payment = CpPayment.find_by(razorpay_payment_id: payment["id"])
      if cp_payment && payment["amount"].present?
        cp_payment.update(
          amount_cents: payment["amount"],
          method_type: payment["method"],
          )
      end
    end

    def find_user_from_notes(entity)
      user_id = entity.dig("notes", "user_id")
      return nil unless user_id.present?

      User.find_by(id: user_id)
    end
  end
end
