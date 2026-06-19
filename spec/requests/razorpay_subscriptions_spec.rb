require "rails_helper"

RSpec.describe "RazorpaySubscriptions" do
  let(:user) { create(:user) }
  let(:razorpay_key_id) { "rzp_test_key123" }
  let(:razorpay_key_secret) { "rzp_test_secret456" }
  let(:monthly_amount_paise) { 9900 }
  let(:yearly_amount_paise) { 99900 }

  def razorpay_response(success:, body:)
    response_class = Class.new do
      def initialize(success, body)
        @success = success
        @body = body
      end

      attr_reader :body

      def success?
        @success
      end

      def parsed_response
        JSON.parse(body)
      end
    end

    response_class.new(success, body.to_json)
  end

  before do
    allow(Settings::General).to receive(:razorpay_key_id).and_return(razorpay_key_id)
    allow(Settings::General).to receive(:razorpay_key_secret).and_return(razorpay_key_secret)
    allow(Settings::General).to receive(:razorpay_monthly_amount_paise).and_return(monthly_amount_paise)
    allow(Settings::General).to receive(:razorpay_yearly_amount_paise).and_return(yearly_amount_paise)
    allow(Settings::General).to receive(:logo_png).and_return("https://careerpolitics.com/cp-logo.png")
  end

  describe "GET /razorpay_subscriptions/new" do
    context "when the user is not signed in" do
      it "redirects to the sign in page" do
        get new_subscription_path
        expect(response).to redirect_to("/magic_links/new")
      end
    end

    context "when the user is signed in" do
      before { sign_in user }

      it "renders the pricing page without calling Razorpay API" do
        get new_subscription_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Subscribe to CP++")
        expect(response.body).to include("Monthly")
      end

      it "derives display price from paise amount" do
        get new_subscription_path

        expect(response.body).to include("₹99")
        expect(response.body).to include("₹999")
      end

      it "redirects with error when no amount is configured" do
        allow(Settings::General).to receive(:razorpay_monthly_amount_paise).and_return(0)
        allow(Settings::General).to receive(:razorpay_yearly_amount_paise).and_return(0)

        get new_subscription_path

        expect(flash[:error]).to eq("Payment plan not configured. Please contact support.")
        expect(response).to have_http_status(:redirect)
      end

      it "redirects already-subscribed users to billing" do
        user.add_role("base_subscriber")
        create(:cp_subscription, user: user)

        get new_subscription_path

        expect(flash[:notice]).to eq("You already have an active CP++ subscription.")
        expect(response).to redirect_to(user_settings_path(:billing))
      end
    end
  end

  describe "POST /razorpay_subscriptions" do
    before { sign_in user }

    it "creates a Razorpay order and returns JSON" do
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: true, body: { "id" => "order_test789", "amount" => 9900, "currency" => "INR" }),
        )

      post subscriptions_path, params: { plan_type: "monthly" }, as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["order_id"]).to eq("order_test789")
      expect(json["key_id"]).to eq(razorpay_key_id)
      expect(json["amount"]).to eq(9900)
    end

    it "sends correct payload to Razorpay Orders API" do
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: true, body: { "id" => "order_test789", "amount" => 9900, "currency" => "INR" }),
        )

      post subscriptions_path, params: { plan_type: "monthly" }, as: :json

      expect(HTTParty).to have_received(:post) do |url, options|
        expect(url).to eq("https://api.razorpay.com/v1/orders")
        expect(options[:basic_auth]).to eq(username: razorpay_key_id, password: razorpay_key_secret)
        body = JSON.parse(options[:body])
        expect(body["amount"]).to eq(9900)
        expect(body["currency"]).to eq("INR")
      end
    end

    it "returns error JSON when Razorpay API fails" do
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: false, body: { "error" => { "description" => "API error" } }),
        )

      post subscriptions_path, params: { plan_type: "monthly" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Unable to create payment order. Please try again.")
    end

    it "returns error when no amount is configured" do
      allow(Settings::General).to receive(:razorpay_monthly_amount_paise).and_return(0)

      post subscriptions_path, params: { plan_type: "monthly" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Plan not configured.")
    end
  end

  describe "POST /razorpay_subscriptions/confirm" do
    let(:payment_id) { "pay_test123" }
    let(:order_id) { "order_test789" }

    before { sign_in user }

    context "with valid signature" do
      let(:valid_signature) do
        OpenSSL::HMAC.hexdigest("SHA256", razorpay_key_secret, "#{order_id}|#{payment_id}")
      end

      it "activates the subscription and creates CpSubscription record" do
        post confirm_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: valid_signature,
          plan_type: "monthly",
        }

        user.reload
        expect(user.roles.pluck(:name)).to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("paying_subscription")
        expect(user.cp_subscriptions.active.count).to eq(1)

        cp_sub = user.cp_subscriptions.active.last
        expect(cp_sub.razorpay_order_id).to eq(order_id)
        expect(cp_sub.plan_type).to eq("monthly")
        expect(cp_sub.amount_cents).to eq(9900)
        expect(user.cp_payments.count).to eq(1)
        expect(response).to redirect_to(user_settings_path(:billing))
      end

      it "does not duplicate the role if already a subscriber" do
        user.add_role("base_subscriber")

        post confirm_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: valid_signature,
          plan_type: "monthly",
        }

        expect(user.reload.roles.where(name: "base_subscriber").count).to eq(1)
      end

      it "expires existing trial when upgrading to paid" do
        trial = create(:cp_subscription, :trial, user: user)

        post confirm_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: valid_signature,
          plan_type: "monthly",
        }

        expect(trial.reload.status).to eq("expired")
        expect(user.reload.cp_subscriptions.active.count).to eq(1)
      end
    end

    context "with missing confirmation params" do
      it "does not raise and redirects with verification error" do
        post confirm_subscriptions_path

        expect(user.reload.roles.pluck(:name)).not_to include("base_subscriber")
        expect(flash[:error]).to include("Payment verification failed")
        expect(response).to redirect_to(user_settings_path(:billing))
      end
    end

    context "with invalid signature" do
      it "does not activate subscription and shows error" do
        post confirm_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: "invalid_signature",
          plan_type: "monthly",
        }

        expect(user.reload.roles.pluck(:name)).not_to include("base_subscriber")
        expect(flash[:error]).to include("Payment verification failed")
        expect(response).to redirect_to(user_settings_path(:billing))
      end
    end
  end

  describe "POST /razorpay_subscriptions/free_trial" do
    context "when the user is not signed in" do
      it "redirects to the sign in page" do
        post free_trial_subscriptions_path
        expect(response).to redirect_to("/magic_links/new")
      end
    end

    context "when the user is signed in" do
      before { sign_in user }

      it "grants CP++ trial access and creates a CpSubscription with expiry" do
        post free_trial_subscriptions_path

        user.reload
        expect(user.roles.pluck(:name)).to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("trial_subscription")
        expect(user.cp_subscriptions.trial.count).to eq(1)

        trial = user.cp_subscriptions.trial.last
        expect(trial.trial_ends_at).to be_within(1.minute).of(7.days.from_now)
        expect(response).to redirect_to(user_settings_path(:billing))
      end

      it "does not change existing paying subscribers" do
        user.add_role("base_subscriber")
        create(:cp_subscription, user: user)

        post free_trial_subscriptions_path

        expect(user.reload.current_subscriber_status).to eq("paying_subscription")
      end
    end
  end

  describe "GET /razorpay_subscriptions/:id/edit" do
    context "when the user is not signed in" do
      it "redirects to the sign in page" do
        get edit_subscription_path("me")
        expect(response).to redirect_to("/magic_links/new")
      end
    end

    context "when the user is signed in with an active subscription" do
      before do
        sign_in user
        create(:cp_subscription, user: user)
      end

      it "renders the edit page with subscription details" do
        get edit_subscription_path("me")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Manage Subscription")
      end
    end

    context "when the user has a trial subscription" do
      before do
        sign_in user
        create(:cp_subscription, :trial, user: user)
      end

      it "renders the edit page with trial info" do
        get edit_subscription_path("me")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Trial")
        expect(response.body).to include("Subscribe Now")
      end
    end

    context "when the user has no active subscription" do
      before { sign_in user }

      it "redirects with an error" do
        get edit_subscription_path("me")

        expect(flash[:error]).to eq("No active subscription found.")
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "DELETE /razorpay_subscriptions/:id" do
    before do
      sign_in user
      user.add_role("base_subscriber")
      user.update(current_subscriber_status: :paying_subscription)
      create(:cp_subscription, user: user)
    end

    context "with correct verification phrase" do
      it "cancels the subscription locally, removes the role, and updates CpSubscription" do
        delete subscription_path("me"), params: { verification: "pleasecancelmysubscription" }

        user.reload
        expect(user.roles.pluck(:name)).not_to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("not_subscribed")
        expect(user.cp_subscriptions.cancelled.count).to eq(1)
        expect(flash[:notice]).to eq("Your subscription has been canceled.")
      end
    end

    context "with incorrect verification phrase" do
      it "does not cancel the subscription" do
        delete subscription_path("me"), params: { verification: "wrong" }

        expect(user.reload.roles.pluck(:name)).to include("base_subscriber")
        expect(flash[:error]).to eq("Invalid verification phrase. Subscription was not canceled.")
      end
    end

    context "when user has no active subscription" do
      before do
        user.cp_subscriptions.update_all(status: :cancelled, cancelled_at: Time.current)
      end

      it "shows an error" do
        delete subscription_path("me"), params: { verification: "pleasecancelmysubscription" }

        expect(flash[:error]).to include("No active subscription found")
      end
    end
  end
end
