require "rails_helper"

RSpec.describe "IncomingWebhooks::RazorpayEventsController" do
  let(:webhook_secret) { "whsec_razorpay_test_secret" }
  let(:user) { create(:user) }

  before do
    allow(IncomingWebhooks::RazorpayEventsController).to receive(:webhook_secret).and_return(webhook_secret)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  def razorpay_signature(payload)
    OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload)
  end

  describe "POST /incoming_webhooks/razorpay_events" do
    context "with invalid signature" do
      it "returns :bad_request" do
        payload = { event: "payment.captured" }.to_json
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => "invalid_sig", "CONTENT_TYPE" => "application/json" },
             as: :json
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when payment.captured" do
      let!(:cp_sub) { create(:cp_subscription, user: user) }
      let!(:cp_payment) do
        create(:cp_payment,
               cp_subscription: cp_sub,
               user: user,
               razorpay_payment_id: "pay_test123",
               amount_cents: 0,
               currency: "INR",
               status: :captured)
      end

      let(:payload) do
        {
          event: "payment.captured",
          payload: {
            payment: {
              entity: {
                id: "pay_test123",
                amount: 9900,
                method: "upi",
                notes: { user_id: user.id.to_s },
              },
            },
          },
        }.to_json
      end

      it "updates the CpPayment record with amount and method" do
        signature = razorpay_signature(payload)
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => signature, "CONTENT_TYPE" => "application/json" },
             as: :json

        cp_payment.reload
        expect(cp_payment.amount_cents).to eq(9900)
        expect(cp_payment.method_type).to eq("upi")
      end
    end

    context "when an unhandled event type is received" do
      let(:payload) { { event: "order.paid", payload: {} }.to_json }

      it "returns :ok and logs the event" do
        signature = razorpay_signature(payload)
        post "/incoming_webhooks/razorpay_events",
             params: payload,
             headers: { "X-Razorpay-Signature" => signature, "CONTENT_TYPE" => "application/json" },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(Rails.logger).to have_received(:info).with(/Unhandled Razorpay event type/)
      end
    end
  end
end
