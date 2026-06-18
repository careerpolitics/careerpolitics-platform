module Subscriptions
  class ExpireTrialsWorker
    include Sidekiq::Job

    sidekiq_options queue: :medium_priority, retry: 3

    # Can be called with specific user_id + subscription_id (scheduled per-trial),
    # or with no args to sweep all expired trials (cron-style).
    def perform(user_id = nil, cp_subscription_id = nil)
      if user_id && cp_subscription_id
        expire_single_trial(user_id, cp_subscription_id)
      else
        expire_all_overdue_trials
      end
    end

    private

    def expire_single_trial(user_id, cp_subscription_id)
      sub = CpSubscription.find_by(id: cp_subscription_id, user_id: user_id, status: :trial)
      return unless sub&.trial_expired?

      revoke_access(sub)
    end

    def expire_all_overdue_trials
      CpSubscription.trials_expiring_before(Time.current).find_each do |sub|
        revoke_access(sub)
      end
    end

    def revoke_access(sub)
      user = sub.user

      sub.update!(status: :expired, cancelled_at: Time.current)

      # Only revoke role if user has no other active/paying subscriptions
      return if user.cp_subscriptions.current.where.not(id: sub.id).exists?

      user.remove_role("base_subscriber")
      user.update(current_subscriber_status: :not_subscribed)
      user.touch
      user.profile&.touch

      Rails.logger.info "Trial expired for user #{user.id}, subscription #{sub.id}"
    end
  end
end
