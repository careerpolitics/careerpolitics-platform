module Users
  class CancelRazorpaySubscriptions
    def initialize(user)
      @user = user
    end

    def call
      return unless user&.cp_subscriptions&.current&.exists?

      user.cp_subscriptions.current.update_all(
        status: :cancelled,
        cancelled_at: Time.current,
        )
      user.remove_role("base_subscriber")
      user.update(current_subscriber_status: :not_subscribed)
      user.touch
      user.profile&.touch

      Rails.logger.info "Cancelled CP++ subscription for user #{user.id}"
    rescue StandardError => e
      Rails.logger.error "Failed to cancel subscriptions for user #{user.id}: #{e.message}"
    end

    private

    attr_reader :user
  end
end
