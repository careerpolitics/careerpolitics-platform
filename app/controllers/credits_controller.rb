class CreditsController < ApplicationController
  before_action :authenticate_user!

  def index
    @user_unspent_credits_count = current_user.credits.unspent.size
    @ledger = Credits::Ledger.call(current_user)

    @organizations = current_user.admin_organizations
  end

  def new
    @credit = Credit.new
    @purchaser = if params[:organization_id].present? && current_user.org_admin?(params[:organization_id])
                   Organization.find_by(id: params[:organization_id])
                 else
                   current_user
                 end
    @organizations = current_user.admin_organizations
    @razorpay_key_id = Settings::General.razorpay_key_id
  end

  # POST /credits/create_order — returns JSON with Razorpay order_id for checkout
  def create_order
    number_to_purchase = params[:credits_count].to_i
    if number_to_purchase < 1
      render json: { error: "Please enter a valid number of credits." }, status: :unprocessable_entity
      return
    end

    not_authorized if params[:organization_id].present? && !current_user.org_admin?(params[:organization_id])

    order = Payments::ProcessCreditPurchase.create_order(
      current_user,
      number_to_purchase,
      organization_id: params[:organization_id],
      )

    if order.success?
      render json: {
        order_id: order.order_id,
        amount: order.amount_in_paise,
        currency: order.currency,
        razorpay_key_id: Settings::General.razorpay_key_id,
      }
    else
      render json: { error: order.error }, status: :unprocessable_entity
    end
  end

  # POST /credits — verifies Razorpay payment and creates credits
  def create
    not_authorized if params[:organization_id].present? && !current_user.org_admin?(params[:organization_id])

    number_to_purchase = params[:credits_count].to_i

    payment = Payments::ProcessCreditPurchase.verify_and_fulfill(
      current_user,
      number_to_purchase,
      razorpay_payment_id: params[:razorpay_payment_id],
      razorpay_order_id: params[:razorpay_order_id],
      razorpay_signature: params[:razorpay_signature],
      organization_id: params[:organization_id],
      )

    if payment.success?
      @purchaser = payment.purchaser
      redirect_to credits_path, notice: I18n.t("credits_controller.done", count: number_to_purchase)
    else
      flash[:error] = payment.error
      redirect_to purchase_credits_path
    end
  end
end
