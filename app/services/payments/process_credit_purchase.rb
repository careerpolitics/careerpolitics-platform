module Payments
  # This service encapsulates purchasing credits via the Razorpay API.
  #
  # Flow:
  #   1. Controller calls .create_order to get a Razorpay Order ID + amount.
  #   2. Frontend opens Razorpay Checkout with that order.
  #   3. On payment success, frontend POSTs back with razorpay_payment_id,
  #      razorpay_order_id, and razorpay_signature.
  #   4. Controller calls .verify_and_fulfill to verify the signature and
  #      create the credits.
  class ProcessCreditPurchase
    class << self
      def create_order(user, credits_count, organization_id: nil)
        new(user, credits_count, organization_id: organization_id).create_order
      end

      def verify_and_fulfill(user, credits_count, razorpay_payment_id:, razorpay_order_id:, razorpay_signature:, organization_id: nil)
        new(user, credits_count, organization_id: organization_id)
          .verify_and_fulfill(razorpay_payment_id: razorpay_payment_id,
                              razorpay_order_id: razorpay_order_id,
                              razorpay_signature: razorpay_signature)
      end
    end

    attr_reader :purchaser, :error, :order_id, :amount_in_paise, :currency

    def initialize(user, credits_count, organization_id: nil)
      @user = user
      @credits_count = credits_count
      @organization_id = organization_id
      @success = false
      @currency = "INR"
    end

    def create_order
      @amount_in_paise = @credits_count * cost_per_credit
      payload = {
        amount: @amount_in_paise,
        currency: @currency,
        receipt: "credits_#{@user.id}_#{Time.current.to_i}",
        notes: {
          user_id: @user.id.to_s,
          credits_count: @credits_count.to_s,
          organization_id: @organization_id.to_s,
        },
      }

      response = HTTParty.post(
        "https://api.razorpay.com/v1/orders",
        basic_auth: { username: Settings::General.razorpay_key_id, password: Settings::General.razorpay_key_secret },
        headers: { "Content-Type" => "application/json" },
        body: payload.to_json,
        timeout: 10,
        )

      if response.success?
        parsed = response.parsed_response
        @order_id = parsed["id"]
        @success = true
      else
        @error = "Unable to create payment order. Please try again."
        @success = false
      end

      self
    end

    def verify_and_fulfill(razorpay_payment_id:, razorpay_order_id:, razorpay_signature:)
      unless verify_signature(razorpay_payment_id, razorpay_order_id, razorpay_signature)
        @error = "Payment verification failed. Please contact support."
        @success = false
        return self
      end

      @amount_in_paise = @credits_count * cost_per_credit
      create_credits
      @success = true
      self
    rescue StandardError => e
      Rails.logger.error "Credit purchase fulfillment error for user #{@user.id}: #{e.message}"
      @error = "An error occurred while processing your purchase."
      @success = false
      self
    end

    def success?
      @success
    end

    private

    def verify_signature(payment_id, order_id, signature)
      expected = OpenSSL::HMAC.hexdigest(
        "SHA256",
        Settings::General.razorpay_key_secret,
        "#{order_id}|#{payment_id}",
        )
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def create_credits
      purchaser = if @organization_id.present?
                    Organization.find(@organization_id)
                  else
                    @user
                  end

      now = Time.current
      unit_cost = cost_per_credit / 100.0
      base_attrs = if @organization_id.present?
                     { organization_id: @organization_id }
                   else
                     { user_id: @user.id }
                   end

      credits_attributes = Array.new(@credits_count) do
        base_attrs.merge(created_at: now, updated_at: now, cost: unit_cost)
      end

      Credit.insert_all(credits_attributes)
      purchaser.update(
        credits_count: purchaser.credits.size,
        spent_credits_count: purchaser.credits.spent.size,
        unspent_credits_count: purchaser.credits.unspent.size,
        )
      @purchaser = purchaser
    end

    def cost_per_credit
      prices = Settings::General.credit_prices_in_cents

      case @credits_count
      when ..9
        prices[:small]
      when 10..99
        prices[:medium]
      when 100..999
        prices[:large]
      else
        prices[:xlarge]
      end
    end
  end
end
