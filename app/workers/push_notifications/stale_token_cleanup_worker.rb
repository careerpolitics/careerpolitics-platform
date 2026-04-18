# frozen_string_literal: true

module PushNotifications
  class StaleTokenCleanupWorker
    include Sidekiq::Job
    sidekiq_options queue: :low_priority, retry: 3

    def perform
      count = Device.where("updated_at < ?", 90.days.ago).delete_all
      Rails.logger.info("[StaleTokenCleanup] Removed #{count} stale device tokens")
    end
  end
end
