require "rails_helper"

RSpec.describe "RazorpaySubscriptions" do
  let(:user) { create(:user) }
  let(:razorpay_key_id) { "rzp_test_key123" }
  let(:razorpay_key_secret) { "rzp_test_secret456" }
  let(:plan_id) { "plan_test123" }

  before do
    allow(Settings::General).to receive(:razorpay_key_id).and_return(razorpay_key_id)
    allow(Settings::General).to receive(:razorpay_key_secret).and_return(razorpay_key_secret)
    allow(Razorpay).to receive(:setup)
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
        ENV["RAZORPAY_PLAN_ID"] = plan_id
      end

      after { ENV.delete("RAZORPAY_PLAN_ID") }

      it "creates a Razorpay subscription and renders the new page" do
        subscription_double = double("Razorpay::Subscription", id: "sub_test789")
        allow(Razorpay::Subscription).to receive(:create).and_return(subscription_double)

        get new_razorpay_subscription_path

        expect(Razorpay::Subscription).to have_received(:create).with(
          hash_including(plan_id: plan_id, quantity: 1),
          )
        expect(response).to have_http_status(:ok)
      end

      it "uses plan param when provided" do
        custom_plan = "plan_custom456"
        subscription_double = double("Razorpay::Subscription", id: "sub_test789")
        allow(Razorpay::Subscription).to receive(:create).and_return(subscription_double)

        get new_razorpay_subscription_path, params: { plan: custom_plan }

        expect(Razorpay::Subscription).to have_received(:create).with(
          hash_including(plan_id: custom_plan),
          )
      end

      it "redirects with error when no plan is configured" do
        ENV.delete("RAZORPAY_PLAN_ID")

        get new_razorpay_subscription_path

        expect(flash[:error]).to eq("Payment plan not configured. Please contact support.")
        expect(response).to have_http_status(:redirect)
      end

      it "handles Razorpay API errors gracefully" do
        allow(Razorpay::Subscription).to receive(:create).and_raise(
          Razorpay::Error.new("API error"),
          )

        get new_razorpay_subscription_path

        expect(flash[:error]).to eq("Unable to create subscription. Please try again.")
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "GET /razorpay_subscriptions/confirm" do
    let(:payment_id) { "pay_test123" }
    let(:subscription_id) { "sub_test789" }

    before { sign_in user }

    context "with valid signature" do
      let(:valid_signature) do
        OpenSSL::HMAC.hexdigest("SHA256", razorpay_key_secret, "#{payment_id}|#{subscription_id}")
      end

      it "activates the subscription and redirects to billing" do
        get confirm_razorpay_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_subscription_id: subscription_id,
          razorpay_signature: valid_signature,
        }

        user.reload
        expect(user.roles.pluck(:name)).to include("base_subscriber")
        expect(user.stripe_id_code).to eq(subscription_id)
        expect(user.current_subscriber_status).to eq("paying_subscription")
        expect(response).to redirect_to(user_settings_path(:billing))
      end

      it "does not duplicate the role if already a subscriber" do
        user.add_role("base_subscriber")

        get confirm_razorpay_subscriptions_path, params: {
          razorpay_payment_id: payment_id,
          razorpay_subscription_id: subscription_id,
          razorpay_signature: valid_signature,
        }

        expect(user.reload.roles.where(name: "base_subscriber").count).to eq(1)
      end
    end

    context "with invalid signature" do
      it "does not activate subscription and shows error" do
        get confirm_razorpay_subscriptions_path, params: {
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

  describe "DELETE /razorpay_subscriptions/:id" do
    before do
      sign_in user
      user.add_role("base_subscriber")
      user.update(stripe_id_code: "sub_test789", current_subscriber_status: :paying_subscription)
    end

    context "with correct verification phrase" do
      it "cancels the subscription and removes the role" do
        subscription_double = double("Razorpay::Subscription", id: "sub_test789")
        allow(Razorpay::Subscription).to receive(:fetch).and_return(subscription_double)
        allow(Razorpay::Subscription).to receive(:cancel)

        delete razorpay_subscription_path("me"), params: { verification: "pleasecancelmysubscription" }

        user.reload
        expect(user.roles.pluck(:name)).not_to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("not_subscribed")
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
      before { user.update(stripe_id_code: nil) }

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
