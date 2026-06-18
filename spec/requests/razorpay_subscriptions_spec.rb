require "rails_helper"

RSpec.describe "RazorpaySubscriptions" do
  let(:user) { create(:user) }
  let(:razorpay_key_id) { "rzp_test_key123" }
  let(:razorpay_key_secret) { "rzp_test_secret456" }
  let(:plan_id) { "plan_test123" }

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
    allow(Settings::General).to receive(:logo_png).and_return("https://careerpolitics.com/cp-logo.png")
    allow(Razorpay).to receive(:setup)
    allow(Razorpay).to receive(:headers=)
  end

  describe "GET /razorpay_subscriptions/new" do
    context "when the user is not signed in" do
      it "redirects to the sign in page" do
        get new_razorpay_subscription_path
        expect(response).to redirect_to("/magic_links/new")
      end
    end

    context "when the user is signed in" do
      before do
        sign_in user
        allow(Settings::General).to receive(:razorpay_plan_id).and_return(plan_id)
      end

      it "renders the pricing page without calling Razorpay API" do
        get new_razorpay_subscription_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("CP++ Premium")
        expect(response.body).to include("Subscribe Now")
        expect(response.body).to include("Unlimited Mock Exams")
      end

      it "renders CP++ branding and FAQ" do
        get new_razorpay_subscription_path

        expect(response.body).to include("subscription-icon")
        expect(response.body).to include("Frequently Asked Questions")
      end

      it "redirects with error when no plan is configured" do
        allow(Settings::General).to receive(:razorpay_plan_id).and_return(nil)

        get new_razorpay_subscription_path

        expect(flash[:error]).to eq("Payment plan not configured. Please contact support.")
        expect(response).to have_http_status(:redirect)
      end

      it "redirects already-subscribed users to billing" do
        user.add_role("base_subscriber")
        user.update!(razorpay_subscription_id: "sub_existing")

        get new_razorpay_subscription_path

        expect(flash[:notice]).to eq("You already have an active CP++ subscription.")
        expect(response).to redirect_to(user_settings_path(:billing))
      end
    end
  end

  describe "POST /razorpay_subscriptions" do
    before do
      sign_in user
      allow(Settings::General).to receive(:razorpay_plan_id).and_return(plan_id)
    end

    it "creates a Razorpay subscription and returns JSON" do
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: true, body: { "id" => "sub_test789" }),
        )

      post razorpay_subscriptions_path, params: {}, as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["subscription_id"]).to eq("sub_test789")
      expect(json["razorpay_key_id"]).to eq(razorpay_key_id)
    end

    it "sends correct payload to Razorpay API" do
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: true, body: { "id" => "sub_test789" }),
        )

      post razorpay_subscriptions_path, params: {}, as: :json

      expect(HTTParty).to have_received(:post) do |url, options|
        expect(url).to eq("https://api.razorpay.com/v1/subscriptions")
        expect(options[:basic_auth]).to eq(username: razorpay_key_id, password: razorpay_key_secret)
        expect(JSON.parse(options[:body])).to include("plan_id" => plan_id, "quantity" => 1)
      end
    end

    it "returns error JSON when Razorpay API fails" do
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: false, body: { "error" => { "description" => "API error" } }),
        )

      post razorpay_subscriptions_path, params: {}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Unable to create subscription. Please try again.")
    end

    it "returns error when no plan is configured" do
      allow(Settings::General).to receive(:razorpay_plan_id).and_return(nil)

      post razorpay_subscriptions_path, params: {}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Payment plan not configured.")
    end
  end

  describe "POST /razorpay_subscriptions/confirm" do
    let(:payment_id) { "pay_test123" }
    let(:subscription_id) { "sub_test789" }

    before do
      sign_in user
      allow(Settings::General).to receive(:razorpay_plan_id).and_return(plan_id)
    end

    context "with valid signature" do
      let(:valid_signature) do
        OpenSSL::HMAC.hexdigest("SHA256", razorpay_key_secret, "#{payment_id}|#{subscription_id}")
      end

      it "activates the subscription and creates CpSubscription record" do
        post confirm_razorpay_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_subscription_id: subscription_id,
          razorpay_signature: valid_signature,
        }

        user.reload
        expect(user.roles.pluck(:name)).to include("base_subscriber")
        expect(user.razorpay_subscription_id).to eq(subscription_id)
        expect(user.current_subscriber_status).to eq("paying_subscription")
        expect(user.cp_subscriptions.active.count).to eq(1)
        expect(user.cp_payments.count).to eq(1)
        expect(response).to redirect_to(user_settings_path(:billing))
      end

      it "does not duplicate the role if already a subscriber" do
        user.add_role("base_subscriber")
        user.update!(razorpay_subscription_id: subscription_id)

        post confirm_razorpay_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_subscription_id: subscription_id,
          razorpay_signature: valid_signature,
        }

        expect(user.reload.roles.where(name: "base_subscriber").count).to eq(1)
      end

      it "expires existing trial when upgrading to paid" do
        trial = create(:cp_subscription, :trial, user: user)

        post confirm_razorpay_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_subscription_id: subscription_id,
          razorpay_signature: valid_signature,
        }

        expect(trial.reload.status).to eq("expired")
        expect(user.reload.cp_subscriptions.active.count).to eq(1)
      end
    end

    context "with missing confirmation params" do
      it "does not raise and redirects with verification error" do
        post confirm_razorpay_subscriptions_path

        expect(user.reload.roles.pluck(:name)).not_to include("base_subscriber")
        expect(flash[:error]).to include("Payment verification failed")
        expect(response).to redirect_to(user_settings_path(:billing))
      end
    end

    context "with invalid signature" do
      it "does not activate subscription and shows error" do
        post confirm_razorpay_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_subscription_id: subscription_id,
          razorpay_signature: "invalid_signature",
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
        post free_trial_razorpay_subscriptions_path
        expect(response).to redirect_to("/magic_links/new")
      end
    end

    context "when the user is signed in" do
      before { sign_in user }

      it "grants CP++ trial access and creates a CpSubscription with expiry" do
        post free_trial_razorpay_subscriptions_path

        user.reload
        expect(user.roles.pluck(:name)).to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("trial_subscription")
        expect(user.razorpay_subscription_id).to be_nil
        expect(user.cp_subscriptions.trial.count).to eq(1)

        trial = user.cp_subscriptions.trial.last
        expect(trial.trial_ends_at).to be_within(1.minute).of(7.days.from_now)
        expect(response).to redirect_to(user_settings_path(:billing))
      end

      it "does not change existing paying subscribers" do
        user.add_role("base_subscriber")
        user.update!(current_subscriber_status: :paying_subscription, razorpay_subscription_id: "sub_test789")

        post free_trial_razorpay_subscriptions_path

        expect(user.reload.current_subscriber_status).to eq("paying_subscription")
        expect(user.razorpay_subscription_id).to eq("sub_test789")
      end
    end
  end

  describe "GET /razorpay_subscriptions/:id/edit" do
    context "when the user is not signed in" do
      it "redirects to the sign in page" do
        get edit_razorpay_subscription_path("me")
        expect(response).to redirect_to("/magic_links/new")
      end
    end

    context "when the user is signed in with an active subscription" do
      before do
        sign_in user
        user.update(razorpay_subscription_id: "sub_test789")
        create(:cp_subscription, user: user, razorpay_subscription_id: "sub_test789")
      end

      it "fetches the subscription and renders the edit page" do
        subscription_double = double("Razorpay::Subscription",
                                     id: "sub_test789",
                                     attributes: { "status" => "active", "current_end" => Time.current.to_i })
        allow(Razorpay::Subscription).to receive(:fetch).with("sub_test789").and_return(subscription_double)

        get edit_razorpay_subscription_path("me")

        expect(Razorpay::Subscription).to have_received(:fetch).with("sub_test789")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Payment History")
      end
    end

    context "when the user has a trial subscription" do
      before do
        sign_in user
        create(:cp_subscription, :trial, user: user)
      end

      it "renders the edit page with trial info" do
        get edit_razorpay_subscription_path("me")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Trial")
        expect(response.body).to include("Subscribe Now")
      end
    end

    context "when the user has no active subscription" do
      before { sign_in user }

      it "redirects with an error" do
        get edit_razorpay_subscription_path("me")

        expect(flash[:error]).to eq("No active subscription found.")
        expect(response).to have_http_status(:redirect)
      end
    end

    context "when Razorpay API fails" do
      before do
        sign_in user
        user.update(razorpay_subscription_id: "sub_test789")
        allow(Razorpay::Subscription).to receive(:fetch).and_raise(Razorpay::Error.new("API error"))
      end

      it "handles the error gracefully" do
        get edit_razorpay_subscription_path("me")

        expect(flash[:error]).to eq("Unable to load subscription details.")
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "DELETE /razorpay_subscriptions/:id" do
    before do
      sign_in user
      user.add_role("base_subscriber")
      user.update(razorpay_subscription_id: "sub_test789", current_subscriber_status: :paying_subscription)
      create(:cp_subscription, user: user, razorpay_subscription_id: "sub_test789")
    end

    context "with correct verification phrase" do
      it "cancels the subscription, removes the role, and updates CpSubscription" do
        subscription_double = double("Razorpay::Subscription", id: "sub_test789")
        allow(Razorpay::Subscription).to receive(:fetch).and_return(subscription_double)
        allow(Razorpay::Subscription).to receive(:cancel)

        delete razorpay_subscription_path("me"), params: { verification: "pleasecancelmysubscription" }

        user.reload
        expect(user.roles.pluck(:name)).not_to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("not_subscribed")
        expect(user.cp_subscriptions.cancelled.count).to eq(1)
        expect(flash[:notice]).to eq("Your subscription has been canceled.")
      end
    end

    context "with incorrect verification phrase" do
      it "does not cancel the subscription" do
        expect(Razorpay::Subscription).not_to receive(:fetch)

        delete razorpay_subscription_path("me"), params: { verification: "wrong" }

        expect(user.reload.roles.pluck(:name)).to include("base_subscriber")
        expect(flash[:error]).to eq("Invalid verification phrase. Subscription was not canceled.")
      end
    end

    context "when user has no active subscription" do
      before { user.update(razorpay_subscription_id: nil) }

      it "shows an error" do
        delete razorpay_subscription_path("me"), params: { verification: "pleasecancelmysubscription" }

        expect(flash[:error]).to include("No active subscription found")
      end
    end

    context "when Razorpay API fails" do
      it "handles the error gracefully" do
        allow(Razorpay::Subscription).to receive(:fetch).and_raise(Razorpay::Error.new("API error"))

        delete razorpay_subscription_path("me"), params: { verification: "pleasecancelmysubscription" }

        expect(flash[:error]).to include("Error canceling subscription")
      end
    end
  end
end
