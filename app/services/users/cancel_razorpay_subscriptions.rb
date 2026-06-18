module Users
  class CancelRazorpaySubscriptions
    def self.call(user)
      new(user).call
    end

    def initialize(user)
      @user = user
    end

    def call
      return unless user&.razorpay_subscription_id.present?

      cancel_subscription
    rescue StandardError => e
      Rails.logger.error "Failed to cancel Razorpay subscriptions for user #{user.id}: #{e.message}"
    end

    private

    attr_reader :user

    def cancel_subscription
      Razorpay.setup(::Settings::General.razorpay_key_id, ::Settings::General.razorpay_key_secret)

      subscription = Razorpay::Subscription.fetch(user.razorpay_subscription_id)
      return unless subscription

      # cancel_at_cycle_end: 0 means cancel immediately
      Razorpay::Subscription.cancel(subscription.id, cancel_at_cycle_end: 0)

      Rails.logger.info "Successfully cancelled Razorpay subscription #{subscription.id} for user #{user.id}"
    rescue Razorpay::Error => e
      Rails.logger.error "Razorpay error for user #{user.id}: #{e.message}"
    end
  end
end
