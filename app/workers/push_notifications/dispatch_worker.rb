# frozen_string_literal: true

module PushNotifications
  class DispatchWorker
    include Sidekiq::Job
    sidekiq_options queue: :default, retry: 3

    def perform(notification_id)
      notification = Notification.find_by(id: notification_id)
      return unless notification

      payload = PayloadFactory.build(notification)
      return unless payload

      payload[:notification_id] = notification.id.to_s

      PushNotifications::Send.call(
        user_ids: [notification.user_id],
        body: payload[:body],
        payload: payload
      )
    end
  end
end
