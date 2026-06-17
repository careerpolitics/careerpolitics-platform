require "rails_helper"

RSpec.describe "IncomingWebhooks::RazorpayEventsController" do
  let(:webhook_secret) { "whsec_razorpay_test_secret" }
  let(:user) { create(:user) }

  before do
    stub_const("IncomingWebhooks::RazorpayEventsController::RAZORPAY_WEBHOOK_SECRET", webhook_secret)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    mailer_double = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    mailer_with_double = instance_double(NotifyMailer, base_subscriber_role_email: mailer_double)
    allow(NotifyMailer).to receive(:with).and_return(mailer_with_double)
  end

  def razorpay_signature(payload)
    OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload)
  end

  describe "POST /incoming_webhooks/razorpay_events" do
    shared_examples "a successful razorpay event" do
      it "returns status :ok" do
        signature = razorpay_signature(payload)
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => signature, "CONTENT_TYPE" => "application/json" },
             as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid signature" do
      it "returns :bad_request" do
        payload = { event: "subscription.activated" }.to_json
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => "invalid_sig", "CONTENT_TYPE" => "application/json" },
             as: :json
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with missing signature" do
      it "returns :bad_request" do
        payload = { event: "subscription.activated" }.to_json
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "CONTENT_TYPE" => "application/json" },
             as: :json
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when subscription.activated" do
      let(:payload) do
        {
          event: "subscription.activated",
          payload: {
            subscription: {
              entity: {
                id: "sub_test123",
                notes: { user_id: user.id.to_s },
              },
            },
          },
        }.to_json
      end

      it_behaves_like "a successful razorpay event"

      it "grants the base_subscriber role and sets subscription status" do
        signature = razorpay_signature(payload)
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => signature, "CONTENT_TYPE" => "application/json" },
             as: :json

        user.reload
        expect(user.roles.pluck(:name)).to include("base_subscriber")
        expect(user.stripe_id_code).to eq("sub_test123")
        expect(user.current_subscriber_status).to eq("paying_subscription")
      end
    end

    context "when subscription.cancelled" do
      let(:payload) do
        {
          event: "subscription.cancelled",
          payload: {
            subscription: {
              entity: {
                id: "sub_test123",
                notes: { user_id: user.id.to_s },
              },
            },
          },
        }.to_json
      end

      before do
        user.add_role("base_subscriber")
        user.update(stripe_id_code: "sub_test123", current_subscriber_status: :paying_subscription)
      end

      it_behaves_like "a successful razorpay event"

      it "removes the base_subscriber role and updates status" do
        signature = razorpay_signature(payload)
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => signature, "CONTENT_TYPE" => "application/json" },
             as: :json

        user.reload
        expect(user.roles.pluck(:name)).not_to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("not_subscribed")
      end
    end

    context "when subscription.halted" do
      let(:payload) do
        {
          event: "subscription.halted",
          payload: {
            subscription: {
              entity: {
                id: "sub_test123",
                notes: { user_id: user.id.to_s },
              },
            },
          },
        }.to_json
      end

      before do
        user.add_role("base_subscriber")
        user.update(stripe_id_code: "sub_test123", current_subscriber_status: :paying_subscription)
      end

      it_behaves_like "a successful razorpay event"

      it "removes the base_subscriber role on payment failure" do
        signature = razorpay_signature(payload)
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => signature, "CONTENT_TYPE" => "application/json" },
             as: :json

        user.reload
        expect(user.roles.pluck(:name)).not_to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("not_subscribed")
      end
    end

    context "when user_id is missing from notes" do
      let(:payload) do
        {
          event: "subscription.activated",
          payload: {
            subscription: {
              entity: {
                id: "sub_test123",
                notes: {},
              },
            },
          },
        }.to_json
      end

      it_behaves_like "a successful razorpay event"

      it "logs a warning and does not crash" do
        signature = razorpay_signature(payload)
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => signature, "CONTENT_TYPE" => "application/json" },
             as: :json

        expect(Rails.logger).to have_received(:warn).with(/no user_id in notes/)
      end
    end
  end
end
