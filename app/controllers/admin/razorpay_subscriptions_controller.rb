module Admin
  class RazorpaySubscriptionsController < Admin::ApplicationController
    layout "admin"

    def index
      @users = subscribed_users.page(params[:page]).per(50)
      @subscriber_role_dates = subscriber_role_dates(@users)
    end

    def cancel
      user = User.find(params[:id])

      if user.stripe_id_code.blank?
        flash[:error] = "No Razorpay subscription ID found for #{user.username}."
        redirect_to admin_razorpay_subscriptions_path and return
      end

      Razorpay.setup(Settings::General.razorpay_key_id, Settings::General.razorpay_key_secret)
      subscription = Razorpay::Subscription.fetch(user.stripe_id_code)
      Razorpay::Subscription.cancel(subscription.id, cancel_at_cycle_end: 0)
      mark_not_subscribed(user)

      flash[:success] = "Cancelled Razorpay subscription for #{user.username}."
      redirect_to admin_razorpay_subscriptions_path
    rescue Razorpay::Error => e
      Rails.logger.error "Admin Razorpay cancellation failed for user #{params[:id]}: #{e.message}"
      flash[:error] = "Unable to cancel Razorpay subscription: #{e.message}"
      redirect_to admin_razorpay_subscriptions_path
    end

    def refund
      user = User.find(params[:id])
      payment_id = params[:payment_id].to_s.strip

      if payment_id.blank?
        flash[:error] = "Enter a Razorpay payment ID to refund."
        redirect_to admin_razorpay_subscriptions_path and return
      end

      refund_razorpay_payment(payment_id)
      mark_not_subscribed(user) if params[:cancel_access].to_s == "1"

      flash[:success] = "Refund initiated for Razorpay payment #{payment_id}."
      redirect_to admin_razorpay_subscriptions_path
    rescue Razorpay::Error => e
      Rails.logger.error "Admin Razorpay refund failed for user #{params[:id]}: #{e.message}"
      flash[:error] = "Unable to refund Razorpay payment: #{e.message}"
      redirect_to admin_razorpay_subscriptions_path
    end

    private

    def authorization_resource
      User
    end

    def subscribed_users
      User.left_joins(:roles)
        .where(
          subscribed_users_sql,
          not_subscribed: User.current_subscriber_statuses[:not_subscribed],
          role: "base_subscriber",
        )
        .distinct
        .order(created_at: :desc)
    end

    def subscribed_users_sql
      <<~SQL.squish
        users.current_subscriber_status <> :not_subscribed
        OR users.stripe_id_code IS NOT NULL
        OR roles.name = :role
      SQL
    end

    def subscriber_role_dates(users)
      role = Role.find_by(name: "base_subscriber")
      return {} unless role

      UserRole.where(role: role, user_id: users.map(&:id)).index_by(&:user_id)
    end

    def mark_not_subscribed(user)
      user.remove_role("base_subscriber")
      user.update(current_subscriber_status: :not_subscribed)
      user.touch
      user.profile&.touch
    end

    def refund_razorpay_payment(payment_id)
      response = HTTParty.post(
        "https://api.razorpay.com/v1/payments/#{payment_id}/refund",
        basic_auth: {
          username: Settings::General.razorpay_key_id,
          password: Settings::General.razorpay_key_secret,
        },
        headers: { "Content-Type" => "application/json" },
        body: {}.to_json,
        timeout: 10,
      )

      parsed_response = response.parsed_response.presence || JSON.parse(response.body)
      return parsed_response if response.success?

      error_message = if parsed_response.is_a?(Hash)
                        parsed_response.dig("error", "description") || parsed_response["error"] || response.body
                      else
                        response.body
                      end
      raise Razorpay::Error, error_message
    rescue JSON::ParserError => e
      raise Razorpay::Error, "Unable to parse Razorpay refund response: #{e.message}"
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Razorpay::Error, "Unable to reach Razorpay refund API: #{e.message}"
    end
  end
end
