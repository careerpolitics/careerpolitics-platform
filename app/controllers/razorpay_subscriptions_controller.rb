class RazorpaySubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :initialize_razorpay

  # GET /razorpay_subscriptions/new
  # Creates a Razorpay Subscription and returns checkout data for the frontend
  def new
    plan_id = if params[:plan].present?
                params[:plan].strip
              else
                Settings::General.razorpay_plan_id&.strip.presence
              end

    Rails.logger.info "Razorpay plan_id resolved to: #{plan_id.inspect} (from Settings: #{Settings::General.razorpay_plan_id.inspect})"

    unless plan_id
      flash[:error] = "Payment plan not configured. Please contact support."
      redirect_back(fallback_location: user_settings_path) and return
    end

    payload = {
      "plan_id" => plan_id,
      "total_count" => (params[:total_count] || 12).to_i,
      "quantity" => 1,
      "customer_notify" => 1,
      "notes" => {
        "user_id" => current_user.id.to_s,
        "username" => current_user.username.to_s,
        "email" => current_user.email.to_s
      }
    }

    Rails.logger.info "[Razorpay Debug] ----------------------------------------"
    Rails.logger.info "[Razorpay Debug] Key ID configured: #{Settings::General.razorpay_key_id.inspect}"
    Rails.logger.info "[Razorpay Debug] Plan ID configured: #{plan_id.inspect}"
    Rails.logger.info "[Razorpay Debug] Sending Payload: #{payload.to_json}"

    subscription = Razorpay::Subscription.create(payload)

    Rails.logger.info "[Razorpay Debug] Success! Subscription ID: #{subscription.id}"
    Rails.logger.info "[Razorpay Debug] ----------------------------------------"

    @subscription_id = subscription.id
    @razorpay_key_id = Settings::General.razorpay_key_id
    @user = current_user
    @plan_id = plan_id

    render :new
  rescue Razorpay::Error => e
    Rails.logger.error "[Razorpay Debug] ----------------------------------------"
    Rails.logger.error "[Razorpay Debug] Razorpay::Error caught!"
    Rails.logger.error "[Razorpay Debug] Message: #{e.message}"
    Rails.logger.error "[Razorpay Debug] Class: #{e.class.name}"
    Rails.logger.error "[Razorpay Debug] Inspect: #{e.inspect}"
    Rails.logger.error "[Razorpay Debug] ----------------------------------------"
    flash[:error] = "Unable to create subscription. Please try again."
    redirect_back(fallback_location: user_settings_path)
  end

  # GET /razorpay_subscriptions/confirm
  # Verifies payment signature and activates subscription
  def confirm
    payment_id = params[:razorpay_payment_id]
    subscription_id = params[:razorpay_subscription_id]
    signature = params[:razorpay_signature]

    # Verify the payment signature
    expected_signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      Settings::General.razorpay_key_secret,
      "#{payment_id}|#{subscription_id}",
      )

    if ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
      unless current_user.base_subscriber?
        current_user.add_role("base_subscriber")
        current_user.update(
          stripe_id_code: subscription_id,
          current_subscriber_status: :paying_subscription,
          )
        current_user.touch
        current_user.profile&.touch
        NotifyMailer.with(user: current_user).base_subscriber_role_email.deliver_later
      end
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

  # GET /razorpay_subscriptions/:id/edit
  # Shows subscription management page
  def edit
    unless current_user.stripe_id_code.present?
      flash[:error] = "No active subscription found."
      redirect_back(fallback_location: user_settings_path) and return
    end

    @subscription = Razorpay::Subscription.fetch(current_user.stripe_id_code)
    @user = current_user
  rescue Razorpay::Error => e
    Rails.logger.error "Razorpay subscription fetch error: #{e.message}"
    flash[:error] = "Unable to load subscription details."
    redirect_back(fallback_location: user_settings_path)
  end

  # DELETE /razorpay_subscriptions/:id
  # Cancels the subscription
  def destroy
    if params[:verification] == "pleasecancelmysubscription" && current_user.stripe_id_code.present?
      subscription = Razorpay::Subscription.fetch(current_user.stripe_id_code)

      if subscription
        Razorpay::Subscription.cancel(subscription.id, cancel_at_cycle_end: 0)
        current_user.remove_role("base_subscriber")
        current_user.update(current_subscriber_status: :not_subscribed)
        current_user.touch
        current_user.profile&.touch
        flash[:notice] = "Your subscription has been canceled."
      else
        flash[:error] = "No active subscription found."
      end
    elsif current_user.stripe_id_code.present?
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

  def initialize_razorpay
    Razorpay.setup(Settings::General.razorpay_key_id, Settings::General.razorpay_key_secret)
  end
end
