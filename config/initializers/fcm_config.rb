# Firebase Cloud Messaging (FCM) configuration
# Ensures FCM is properly configured for push notifications

Rails.application.config.after_initialize do
  fcm_configured =
    ApplicationConfig['RPUSH_FCM_JSON'].present? ||
    ApplicationConfig['RPUSH_FCM_KEY'].present?

  if fcm_configured
    Rails.logger.info(
      "FCM is configured for Android push notifications"
    )
  else
    Rails.logger.warn(
      "FCM is not configured. Set RPUSH_FCM_JSON (Firebase service account JSON)"
    )
  end

  ensure_android_consumer_app
end

def ensure_android_consumer_app
  ConsumerApp.find_or_create_by!(
    app_bundle: "com.murari.careerpolitics",
    platform: "android"
  )

  Rails.logger.info(
    "CareerPolitics Android consumer app initialized"
  )
rescue StandardError => e
  Rails.logger.error(
    "Failed to initialize CareerPolitics consumer app: #{e.message}"
  )
end
