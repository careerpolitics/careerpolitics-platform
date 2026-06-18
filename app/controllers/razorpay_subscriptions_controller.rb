class RazorpaySubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :initialize_razorpay, only: %i[create edit destroy]
  before_action :redirect_if_already_subscribed, only: %i[new create free_trial]

  # GET /razorpay_subscriptions/new
  # Renders the pricing / landing page — NO Razorpay API call here.
  def new
    @user = current_user
    @razorpay_key_id = Settings::General.razorpay_key_id
    @monthly_plan_id = Settings::General.razorpay_plan_id&.strip.presence
    @yearly_plan_id = Settings::General.razorpay_yearly_plan_id&.strip.presence

    unless @monthly_plan_id || @yearly_plan_id
      flash[:error] = "Payment plan not configured. Please contact support."
      redirect_back(fallback_location: user_settings_path) and return
    end

    render :new
  end

  # POST /razorpay_subscriptions
  # Creates a Razorpay Subscription object and returns checkout data as JSON.
  def create
    plan_id = resolve_plan_id

    unless plan_id
      render json: { error: "Payment plan not configured." }, status: :unprocessable_entity and return
    end

    payload = {
      "plan_id" => plan_id,
      "total_count" => 1,
      "quantity" => 1,
      "customer_notify" => 1,
      "notes" => {
        "user_id" => current_user.id.to_s,
        "username" => current_user.username.to_s,
        "email" => current_user.email.to_s,
      },
    }

    subscription = create_razorpay_subscription(payload)

    render json: {
      subscription_id: subscription.fetch("id"),
      razorpay_key_id: Settings::General.razorpay_key_id,
      user_name: current_user.name,
      user_email: current_user.email,
      user_id: current_user.id,
    }
  rescue Razorpay::Error => e
    Rails.logger.error "[Razorpay] Subscription creation failed: #{e.message}"
    render json: { error: "Unable to create subscription. Please try again." }, status: :unprocessable_entity
  end

  # POST /razorpay_subscriptions/confirm
  # Verifies payment signature and activates subscription
  def confirm
    payment_id = params[:razorpay_payment_id]
    subscription_id = params[:razorpay_subscription_id]
    signature = params[:razorpay_signature]

    unless payment_id.present? && subscription_id.present? && signature.present?
      Rails.logger.error "Razorpay confirm missing payment parameters for user #{current_user.id}"
      flash[:error] = "Payment verification failed. Please contact support if you were charged."
      redirect_to user_settings_path(:billing) and return
    end

    expected_signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      Settings::General.razorpay_key_secret,
      "#{payment_id}|#{subscription_id}",
      )

    if signature.bytesize == expected_signature.bytesize &&
       ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
      activate_subscription(subscription_id, payment_id)
      flash[:notice] = "Welcome to CP++! Your subscription is now active."
    else
      Rails.logger.error "Razorpay signature verification failed for user #{current_user.id}"
      flash[:error] = "Payment verification failed. Please contact support if you were charged."
    end

    redirect_to user_settings_path(:billing)
  rescue StandardError => e
    Rails.logger.error "Razorpay confirm error for user #{current_user.id}: #{e.message}"
    flash[:error] = "An error occurred. Please contact support."
    redirect_to user_settings_path(:billing)
  end

  # POST /razorpay_subscriptions/free_trial
  # Grants CP++ trial access without collecting payment details.
  def free_trial
    if current_user.cp_subscriptions.where(status: %i[trial active]).exists?
      flash[:notice] = "You already have an active subscription or trial."
      redirect_to user_settings_path(:billing) and return
    end

    trial_days = 7

    cp_sub = current_user.cp_subscriptions.create!(
      status: :trial,
      provider: "razorpay",
      trial_ends_at: trial_days.days.from_now,
      current_period_start: Time.current,
      current_period_end: trial_days.days.from_now,
      )

    current_user.add_role("base_subscriber")
    current_user.update!(current_subscriber_status: :trial_subscription)
    current_user.touch
    current_user.profile&.touch
    NotifyMailer.with(user: current_user).base_subscriber_role_email.deliver_later

    # Schedule trial expiration check
    Subscriptions::ExpireTrialsWorker.perform_in(
      (trial_days.days + 1.hour).to_i,
      current_user.id,
      cp_sub.id,
      )

    flash[:notice] = "Your free #{trial_days}-day CP++ trial is active. You now have unlimited mock exam access."
    redirect_to user_settings_path(:billing)
  end

  # GET /razorpay_subscriptions/:id/edit
  # Shows subscription management page
  def edit
    @cp_subscription = current_user.cp_subscriptions.current.last
    @payments = current_user.cp_payments.successful.recent_first.limit(10)
    @user = current_user

    unless @cp_subscription || current_user.razorpay_subscription_id.present?
      flash[:error] = "No active subscription found."
      redirect_back(fallback_location: user_settings_path) and return
    end

    if current_user.razorpay_subscription_id.present?
      @razorpay_subscription = Razorpay::Subscription.fetch(current_user.razorpay_subscription_id)
    end
  rescue Razorpay::Error => e
    Rails.logger.error "Razorpay subscription fetch error: #{e.message}"
    flash[:error] = "Unable to load subscription details."
    redirect_back(fallback_location: user_settings_path)
  end

  # DELETE /razorpay_subscriptions/:id
  # Cancels the subscription
  def destroy
    if params[:verification] == "pleasecancelmysubscription" && current_user.razorpay_subscription_id.present?
      Razorpay::Subscription.cancel(current_user.razorpay_subscription_id, cancel_at_cycle_end: 0)
      cancel_user_subscription
      flash[:notice] = "Your subscription has been canceled."
    elsif current_user.razorpay_subscription_id.present?
      flash[:error] = "Invalid verification phrase. Subscription was not canceled."
    else
      flash[:error] = "No active subscription found. Please contact us if you believe this is an error."
    end

    redirect_back(fallback_location: user_settings_path)
  rescue Razorpay::Error => e
    Rails.logger.error "Razorpay subscription cancel error: #{e.message}"
    flash[:error] = "Error canceling subscription: #{e.message}"
    redirect_back(fallback_location: user_settings_path)
  end

  private

  def resolve_plan_id
    case params[:plan_type].to_s
    when "yearly"
      Settings::General.razorpay_yearly_plan_id&.strip.presence
    else
      Settings::General.razorpay_plan_id&.strip.presence
    end
  end

  def redirect_if_already_subscribed
    return unless current_user.cached_base_subscriber? && current_user.razorpay_subscription_id.present?

    flash[:notice] = "You already have an active CP++ subscription."
    redirect_to user_settings_path(:billing)
  end

  def activate_subscription(subscription_id, payment_id)
    return if current_user.base_subscriber? && current_user.razorpay_subscription_id == subscription_id

    # Cancel any existing trial subscription record
    current_user.cp_subscriptions.trial.update_all(status: :expired, cancelled_at: Time.current)

    cp_sub = current_user.cp_subscriptions.create!(
      razorpay_subscription_id: subscription_id,
      razorpay_plan_id: resolve_plan_id,
      status: :active,
      provider: "razorpay",
      current_period_start: Time.current,
      )

    # Record the first payment
    cp_sub.cp_payments.create!(
      user: current_user,
      razorpay_payment_id: payment_id,
      amount_cents: 0, # actual amount comes via webhook
      currency: "INR",
      status: :captured,
      paid_at: Time.current,
      )

    current_user.add_role("base_subscriber") unless current_user.base_subscriber?
    current_user.update(
      razorpay_subscription_id: subscription_id,
      current_subscriber_status: :paying_subscription,
      )
    current_user.touch
    current_user.profile&.touch
    NotifyMailer.with(user: current_user).base_subscriber_role_email.deliver_later
  end

  def cancel_user_subscription
    current_user.cp_subscriptions.current.update_all(
      status: :cancelled,
      cancelled_at: Time.current,
      )
    current_user.remove_role("base_subscriber")
    current_user.update(current_subscriber_status: :not_subscribed)
    current_user.touch
    current_user.profile&.touch
  end

  def create_razorpay_subscription(payload)
    response = HTTParty.post(
      "https://api.razorpay.com/v1/subscriptions",
      basic_auth: {
        username: Settings::General.razorpay_key_id,
        password: Settings::General.razorpay_key_secret,
      },
      body: payload.to_json,
      headers: { "Content-Type" => "application/json" },
      timeout: 10,
      )

    parsed_response = response.parsed_response.presence || JSON.parse(response.body)
    return parsed_response if response.success?

    error_message = razorpay_error_message(parsed_response, response.body)
    raise Razorpay::Error, error_message
  rescue JSON::ParserError => e
    raise Razorpay::Error, "Unable to parse Razorpay subscription response: #{e.message}"
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    raise Razorpay::Error, "Unable to reach Razorpay subscriptions API: #{e.message}"
  end

  def razorpay_error_message(parsed_response, raw_body)
    return raw_body unless parsed_response.is_a?(Hash)

    parsed_response.dig("error", "description") || parsed_response["error"] || raw_body
  end

  def initialize_razorpay
    Razorpay.setup(Settings::General.razorpay_key_id, Settings::General.razorpay_key_secret)
  end
end
