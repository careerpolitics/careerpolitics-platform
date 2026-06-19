class RazorpaySubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_already_subscribed, only: %i[new create free_trial]

  # GET /razorpay_subscriptions/new
  # Renders the pricing / landing page — NO Razorpay API call here.
  def new
    @user = current_user
    @razorpay_key_id = Settings::General.razorpay_key_id
    @monthly_amount_paise = Settings::General.razorpay_monthly_amount_paise
    @yearly_amount_paise = Settings::General.razorpay_yearly_amount_paise
    @monthly_plan_amount = @monthly_amount_paise&.positive? ? "₹#{@monthly_amount_paise / 100}" : "₹99"
    @yearly_plan_amount = @yearly_amount_paise&.positive? ? "₹#{@yearly_amount_paise / 100}" : "₹999"

    unless @monthly_amount_paise&.positive? || @yearly_amount_paise&.positive?
      flash[:error] = "Payment plan not configured. Please contact support."
      redirect_back(fallback_location: user_settings_path) and return
    end

    render :new
  end

  # POST /razorpay_subscriptions
  # Creates a Razorpay Subscription object and returns checkout data as JSON.
  def create
    amount_paise = resolve_amount_paise

    unless amount_paise&.positive?
      render json: { error: "Plan not configured." }, status: :unprocessable_entity and return
    end

    payload = {
      "amount" => amount_paise,
      "currency" => "INR",
      "receipt" => "cp_sub_#{current_user.id}_#{Time.current.to_i}",
      "notes" => {
        "user_id" => current_user.id.to_s,
        "username" => current_user.username.to_s,
        "email" => current_user.email.to_s,
        "plan_type" => params[:plan_type].to_s,
      },
    }

    response = create_razorpay_order(payload)
    parsed = response.parsed_response

    render json: {
      order_id: parsed["id"],
      amount: parsed["amount"],
      currency: parsed["currency"],
      key_id: Settings::General.razorpay_key_id,
      plan_type: params[:plan_type].to_s,
      user_name: current_user.name,
      user_email: current_user.email,
      user_id: current_user.id,
    }
  rescue Razorpay::Error => e
    Rails.logger.error "[Razorpay] Order creation failed: #{e.message}"
    render json: { error: "Unable to create payment order. Please try again." }, status: :unprocessable_entity
  end

  # POST /razorpay_subscriptions/confirm
  # Verifies payment signature and activates subscription
  def confirm
    payment_id = params[:razorpay_payment_id]
    order_id = params[:razorpay_order_id]
    signature = params[:razorpay_signature]
    plan_type = params[:plan_type].to_s

    unless payment_id.present? && order_id.present? && signature.present?
      flash[:error] = "Payment verification failed. Please contact support if you were charged."
      redirect_to user_settings_path(:billing) and return
    end

    expected_signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      Settings::General.razorpay_key_secret,
      "#{order_id}|#{payment_id}",
      )

    if signature.bytesize == expected_signature.bytesize &&
       ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
      activate_subscription(order_id, payment_id, plan_type)
      flash[:notice] = "Welcome to CP++! Your subscription is now active."
    else
      flash[:error] = "Payment verification failed."
    end

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

    unless @cp_subscription
      flash[:error] = "No active subscription found."
      redirect_back(fallback_location: user_settings_path) and return
    end
  end

  # DELETE /razorpay_subscriptions/:id
  # Cancels the subscription
  def destroy
    cp_sub = current_user.cp_subscriptions.current.last

    unless cp_sub
      flash[:error] = "No active subscription found. Please contact us if you believe this is an error."
      redirect_back(fallback_location: user_settings_path) and return
    end

    unless params[:verification] == "pleasecancelmysubscription"
      flash[:error] = "Invalid verification phrase. Subscription was not canceled."
      redirect_back(fallback_location: user_settings_path) and return
    end

    cancel_user_subscription
    flash[:notice] = "Your subscription has been canceled."
    redirect_back(fallback_location: user_settings_path)
  end

  private


  def redirect_if_already_subscribed
    return unless current_user.cached_base_subscriber? && current_user.cp_subscriptions.current.active.exists?

    flash[:notice] = "You already have an active CP++ subscription."
    redirect_to user_settings_path(:billing)
  end

  def activate_subscription(order_id, payment_id, plan_type)
    current_user.cp_subscriptions.trial.update_all(status: :expired, cancelled_at: Time.current)

    amount_paise = resolve_amount_paise
    period_end = resolve_plan_period_end(plan_type)

    cp_sub = current_user.cp_subscriptions.create!(
      razorpay_order_id: order_id,
      plan_type: plan_type.presence || "monthly",
      status: :active,
      provider: "razorpay",
      amount_cents: amount_paise,
      currency: "INR",
      current_period_start: Time.current,
      current_period_end: period_end,
      )

    cp_sub.cp_payments.create!(
      user: current_user,
      razorpay_payment_id: payment_id,
      amount_cents: amount_paise,
      currency: "INR",
      status: :captured,
      paid_at: Time.current,
      )

    current_user.add_role("base_subscriber") unless current_user.base_subscriber?
    current_user.update(current_subscriber_status: :paying_subscription)
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

  def create_razorpay_order(payload)
    response = HTTParty.post(
      "https://api.razorpay.com/v1/orders",
      basic_auth: {
        username: Settings::General.razorpay_key_id,
        password: Settings::General.razorpay_key_secret,
      },
      headers: { "Content-Type" => "application/json" },
      body: payload.to_json,
      timeout: 10,
      )

    return response if response.success?

    parsed_response = JSON.parse(response.body)
    error_message = razorpay_error_message(parsed_response, response.body)
    raise Razorpay::Error, error_message
  rescue JSON::ParserError => e
    raise Razorpay::Error, "Unable to parse Razorpay order response: #{e.message}"
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    raise Razorpay::Error, "Unable to reach Razorpay orders API: #{e.message}"
  end

  def razorpay_error_message(parsed_response, raw_body)
    return raw_body unless parsed_response.is_a?(Hash)

    parsed_response.dig("error", "description") || parsed_response["error"] || raw_body
  end

  def resolve_amount_paise
    case params[:plan_type].to_s
    when "yearly"
      Settings::General.razorpay_yearly_amount_paise
    else
      Settings::General.razorpay_monthly_amount_paise
    end
  end

  def resolve_plan_period_end(plan_type)
    case plan_type
    when "yearly"
      12.months.from_now
    else
      1.month.from_now
    end
  end
end
