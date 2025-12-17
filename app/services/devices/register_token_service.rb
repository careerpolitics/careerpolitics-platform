module Devices
  class RegisterTokenService
    def self.call(user:, token:, platform:, app_bundle:)
      new(user, token, platform, app_bundle).call
    end

    def initialize(user, token, platform, app_bundle)
      @user       = user
      @token      = token
      @platform   = platform
      @app_bundle = app_bundle
    end

    def call
      consumer_app = ConsumerApp.find_or_create_by!(
        app_bundle: @app_bundle,
        platform: @platform,
        )
      device = Device.find_or_initialize_by(
        user: @user,
        consumer_app: consumer_app,
        platform: @platform,
        )

      device.device_token = token

      if device.save
        Rails.logger.info(
          "Device registered successfully. user_id=#{user.id}, platform=#{platform}",
          )
        device
      else
        Rails.logger.error(
          "Failed to register device. errors=#{device.errors.full_messages.join(', ')}",
          )
        nil
      end
    end
  end
end
