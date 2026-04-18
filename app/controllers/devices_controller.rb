class DevicesController < ApplicationController
  # Device's belongs_to :user association enforces that only authenticated
  # users are able to register devices. This replaces the Authenticated Users
  # Pusher Beams solution.
  # See: https://github.com/forem/forem/pull/12419/files#r563906038

  # Require authentication for all actions
  before_action :authenticate_user!

  # Skip CSRF for API endpoints (mobile apps)
  skip_before_action :verify_authenticity_token, only: %i[create destroy fcm_token]

  rescue_from ActiveRecord::ActiveRecordError, ArgumentError do |exc|
    Rails.logger.error "DevicesController Error: #{exc.class.name}: #{exc.message}"
    Rails.logger.error exc.backtrace
    render json: { error: exc.message, status: 422 }, status: :unprocessable_entity
  end

  def create
    # Validate required parameters
    unless params[:token].present? && params[:platform].present? && params[:app_bundle].present?
      Rails.logger.debug "DevicesController#create - Missing required parameters"
      return render json: { error: "Missing required parameters", missing: %i[token platform app_bundle],
                            status: :bad_request },
                    status: :bad_request
    end

    # Find or create ConsumerApp
    app_bundle = params[:app_bundle]
    platform   = params[:platform]

    consumer_app = ConsumerApp.find_or_create_by(
      app_bundle: app_bundle,
      platform: platform,
      )

    # Find existing device or initialize new one (prevents duplicates)
    device = Device.find_or_initialize_by(
      user: current_user,
      consumer_app: consumer_app,
      platform: platform,
      )

    Rails.logger.info "DevicesController#create - User: #{current_user.id}, Token: #{params[:token][0..20]}..."

    # Update token (allows token refresh)
    device.token = params[:token]

    if device.save
      Rails.logger.debug "DevicesController#create - Device created/updated ##{device.id}"
      render json: { id: device.id, status: :created }, status: :created
    else
      Rails.logger.warn "DevicesController#create - Failed: #{device.errors.full_messages.join(', ')}"
      render json: { error: device.errors_as_sentence, status: :bad_request }, status: :bad_request
    end
  end

  def destroy
    device = Device.find_by(unauthenticated_params)


    unless device
      render json: { error: I18n.t("devices_controller.not_found"), status: 404 }, status: :not_found
      return
    end

    device.destroy

    if device.destroyed?
      head :no_content
    else
      render json: { error: device.errors_as_sentence, status: :bad_request }, status: :bad_request
    end
  end

  def fcm_token
    Rails.logger.debug "DevicesController#fcm_token - User: #{current_user.id})"


    if params[:fcm_token].blank?
      Rails.logger.warn "FCM token missing in params"
      return render json: { error: "FCM token is required" }, status: :bad_request
    end


    app_bundle = params[:app_bundle].presence || "com.murari.careerpolitics"
    platform_param = params[:platform].presence&.downcase || "android"


    # Map platform string to Device enum
    platform = case platform_param
               when "android" then "Android"
               when "ios" then "iOS"
               else "Android"
               end


    Rails.logger.debug "DevicesController#fcm_token - ConsumerApp: #{app_bundle}/#{platform}"


    consumer_app = ConsumerApp.find_or_create_by(
      app_bundle: app_bundle,
      platform: platform
    )

    device = Device.find_or_initialize_by(
      user: current_user,
      consumer_app: consumer_app,
      platform: platform
    )

    device.token = params[:fcm_token]


    if device.save
      Rails.logger.debug "DevicesController#fcm_token - Device saved ##{device.id}"
      render json: { success: true, device_id: device.id }, status: :ok
    else
      Rails.logger.warn "DevicesController#fcm_token -failed: #{device.errors.full_messages.join(', ')}"
      render json: {
        error: "Failed to register device",
        details: device.errors.full_messages
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Unexpected error in fcm_token: #{e.class.name} - #{e.message}"
    Rails.logger.error e.backtrace
    render json: { error: "Internal server error: #{e.message}" }, status: :internal_server_error
  end

  private

  def unauthenticated_params
    {
      user_id: params[:id],
      platform: params[:platform],
      token: params[:token],
      consumer_app: ConsumerApp.find_by(app_bundle: params[:app_bundle], platform: params[:platform]),
    }
  end
end
