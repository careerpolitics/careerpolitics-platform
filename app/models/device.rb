class Device < ApplicationRecord
  belongs_to :consumer_app
  belongs_to :user

  IOS = "iOS".freeze
  ANDROID = "Android".freeze

  enum platform: { android: ANDROID, ios: IOS }

  validates :platform, inclusion: { in: platforms.keys }
  validates :token, presence: true
  validates :token, uniqueness: { scope: %i[user_id platform consumer_app_id] }

  def create_notification(title, body, payload)
    # There's no need to create notifications for Consumer Apps that aren't
    # operational. This happens when credentials aren't configured or delivery
    # errors have been raised (i.e. expired authentication certificates)
    return unless consumer_app.operational?

    if android?
      android_notification(title, body, payload)
    elsif ios?
      ios_notification(title, body, payload)
    end
  end

  private

  def ios_notification(title, body, payload)
    n = Rpush::Apns2::Notification.new
    n.device_token = token
    n.app = ConsumerApps::RpushAppQuery.call(
      app_bundle: consumer_app.app_bundle,
      platform: platform,
      )
    n.data = {
      aps: {
        alert: {
          title: Settings::Community.community_name,
          subtitle: title,
          body: body.truncate(512)
        },
        "thread-id": Settings::Community.community_name,
        sound: "default",
        # This key is required to modify the notification in the iOS app: https://developer.apple.com/documentation/usernotifications/modifying_content_in_newly_delivered_notifications#2942066
        "mutable-content": 1
      },
      data: payload
    }
    n.save!
  end

  def android_notification(title, body, payload)
    n = Rpush::Client::Redis::Fcm::Notification.new
    n.app = ConsumerApps::RpushAppQuery.call(
      app_bundle: consumer_app.app_bundle,
      platform: platform
    )

    n.device_token = token
    n.priority = payload.is_a?(Hash) && payload[:priority] == "high" ? "high" : "normal"
    n.content_available = true

    # ---------------------------------------
    # Notification (visible UI)
    # ---------------------------------------
    notification_hash = {
      title: title,
      body: body
    }

    if payload.is_a?(Hash)
      notification_hash[:channel_id] = payload[:channel] if payload[:channel].present?
      notification_hash[:color] = payload[:color] if payload[:color].present?
      notification_hash[:icon] = payload[:icon] if payload[:icon].present?
    end

    notification_hash.compact!
    n.notification = notification_hash

    # ---------------------------------------
    # Data payload (DEEPLINK MUST BE HERE)
    # ---------------------------------------
    data_payload = payload.is_a?(Hash) ? payload : {}

    n.data = data_payload

    # ---------------------------------------
    # 🔍 DEBUG LOGS
    # ---------------------------------------
    Rails.logger.info("[FCM][ANDROID] device_token=#{token.truncate(20)}")
    Rails.logger.info("[FCM][ANDROID] notification=#{notification_hash}")
    Rails.logger.info("[FCM][ANDROID] data_payload=#{data_payload}")
    Rails.logger.info("[FCM][ANDROID] deeplink_url=#{data_payload[:url]}")

    n.save!
  end


end
