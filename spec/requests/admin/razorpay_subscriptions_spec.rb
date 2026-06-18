require "rails_helper"

RSpec.describe "Admin::RazorpaySubscriptions" do
  let(:admin) { create(:user, :super_admin) }
  let(:subscriber) do
    create(:user, current_subscriber_status: :paying_subscription, razorpay_subscription_id: "sub_test789")
  end

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
    sign_in admin
    allow(Settings::General).to receive(:razorpay_key_id).and_return("rzp_test_key")
    allow(Settings::General).to receive(:razorpay_key_secret).and_return("rzp_test_secret")
  end

  describe "GET /admin/member_manager/razorpay_subscriptions" do
    it "shows subscribed users and subscription details" do
      subscriber.add_role("base_subscriber")

      get admin_subscriptions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(subscriber.username)
      expect(response.body).to include("paying_subscription")
      expect(response.body).to include("sub_test789")
      expect(response.body).to include("Cancel subscription")
      expect(response.body).to include("Razorpay payment ID")
    end
  end

  describe "POST /admin/member_manager/razorpay_subscriptions/:id/cancel" do
    it "cancels the Razorpay subscription and removes subscriber access" do
      subscriber.add_role("base_subscriber")
      subscription = double("Razorpay::Subscription", id: "sub_test789")
      allow(Razorpay).to receive(:setup)
      allow(Razorpay::Subscription).to receive(:fetch).with("sub_test789").and_return(subscription)
      allow(Razorpay::Subscription).to receive(:cancel)

      post cancel_admin_subscription_path(subscriber)

      expect(Razorpay::Subscription).to have_received(:cancel).with("sub_test789", cancel_at_cycle_end: 0)
      expect(subscriber.reload.current_subscriber_status).to eq("not_subscribed")
      expect(subscriber.roles.pluck(:name)).not_to include("base_subscriber")
      expect(response).to redirect_to(admin_subscriptions_path)
    end
  end

  describe "POST /admin/member_manager/razorpay_subscriptions/:id/refund" do
    it "refunds the provided Razorpay payment and removes access when requested" do
      subscriber.add_role("base_subscriber")
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: true, body: { "id" => "rfnd_test123" }),
        )

      post refund_admin_subscription_path(subscriber), params: {
        payment_id: "pay_test123",
        cancel_access: "1",
      }

      expect(HTTParty).to have_received(:post) do |url, options|
        expect(url).to eq("https://api.razorpay.com/v1/payments/pay_test123/refund")
        expect(options[:basic_auth]).to eq(username: "rzp_test_key", password: "rzp_test_secret")
      end
      expect(subscriber.reload.current_subscriber_status).to eq("not_subscribed")
      expect(subscriber.roles.pluck(:name)).not_to include("base_subscriber")
      expect(response).to redirect_to(admin_subscriptions_path)
    end

    it "requires a payment ID" do
      post refund_admin_subscription_path(subscriber), params: { payment_id: "" }

      expect(flash[:error]).to eq("Enter a Razorpay payment ID to refund.")
      expect(response).to redirect_to(admin_subscriptions_path)
    end
  end
end
