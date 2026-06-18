module Subscriptions
  class RevokeHaltedAccessWorker
    include Sidekiq::Job

    sidekiq_options queue: :medium_priority, retry: 3

    # Revokes CP++ access if the subscription is still halted after the grace period.
    def perform(user_id, cp_subscription_id)
      sub = CpSubscription.find_by(id: cp_subscription_id, user_id: user_id)
      return unless sub&.halted?

      user = sub.user
      sub.update!(status: :cancelled, cancelled_at: Time.current)

      # Only revoke if no other active subscriptions
      return if user.cp_subscriptions.current.exists?

      user.remove_role("base_subscriber")
      user.update(current_subscriber_status: :not_subscribed)
      user.touch
      user.profile&.touch

      Rails.logger.info "Halted subscription revoked after grace period for user #{user_id}, subscription #{cp_subscription_id}"
    end
  end
end
