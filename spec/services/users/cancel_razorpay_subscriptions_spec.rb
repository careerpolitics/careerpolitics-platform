require "rails_helper"

RSpec.describe Users::CancelRazorpaySubscriptions do
  let(:user) { create(:user, razorpay_subscription_id: "sub_test123") }
  let(:subscription_double) { double("Razorpay::Subscription", id: "sub_test123") }

  before do
    allow(Settings::General).to receive(:razorpay_key_id).and_return("rzp_test_key")
    allow(Settings::General).to receive(:razorpay_key_secret).and_return("rzp_test_secret")
    allow(Razorpay).to receive(:setup)
    allow(Razorpay::Subscription).to receive(:fetch).and_return(subscription_double)
    allow(Razorpay::Subscription).to receive(:cancel)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe ".call" do
    it "cancels the Razorpay subscription for the user" do
      described_class.call(user)

      expect(Razorpay::Subscription).to have_received(:fetch).with("sub_test123")
      expect(Razorpay::Subscription).to have_received(:cancel).with("sub_test123", cancel_at_cycle_end: 0)
    end

    it "logs successful cancellation" do
      described_class.call(user)

      expect(Rails.logger).to have_received(:info).with(
        "Successfully cancelled Razorpay subscription sub_test123 for user #{user.id}",
        )
    end

    context "when user has no razorpay_subscription_id" do
      let(:user) { create(:user, razorpay_subscription_id: nil) }

      it "does not attempt to cancel" do
        expect(Razorpay::Subscription).not_to receive(:fetch)
        described_class.call(user)
      end
    end

    context "when user is nil" do
      it "does not attempt to cancel" do
        expect(Razorpay::Subscription).not_to receive(:fetch)
        described_class.call(nil)
      end
    end

    context "when Razorpay API returns an error" do
      before do
        allow(Razorpay::Subscription).to receive(:fetch).and_raise(Razorpay::Error.new("Not found"))
      end

      it "logs the error but does not raise it" do
        expect { described_class.call(user) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/Razorpay error for user #{user.id}/)
      end
    end

    context "when any other error occurs" do
      before do
        allow(Razorpay::Subscription).to receive(:fetch).and_raise(StandardError.new("Unexpected"))
      end

      it "logs the error but does not raise it" do
        expect { described_class.call(user) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(
          "Failed to cancel Razorpay subscriptions for user #{user.id}: Unexpected",
          )
      end
    end
  end
end
