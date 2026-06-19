require "rails_helper"

RSpec.describe Users::CancelRazorpaySubscriptions do
  let(:user) { create(:user) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe ".call" do
    context "when user has an active subscription" do
      before do
        user.add_role("base_subscriber")
        user.update!(current_subscriber_status: :paying_subscription)
        create(:cp_subscription, user: user)
      end

      it "cancels the CpSubscription locally" do
        described_class.call(user)

        expect(user.cp_subscriptions.cancelled.count).to eq(1)
        expect(user.cp_subscriptions.current.count).to eq(0)
      end

      it "removes base_subscriber role and updates status" do
        described_class.call(user)

        user.reload
        expect(user.roles.pluck(:name)).not_to include("base_subscriber")
        expect(user.current_subscriber_status).to eq("not_subscribed")
      end

      it "logs successful cancellation" do
        described_class.call(user)

        expect(Rails.logger).to have_received(:info).with(
          "Cancelled CP++ subscription for user #{user.id}",
          )
      end
    end

    context "when user has no active subscription" do
      it "does not raise an error" do
        expect { described_class.call(user) }.not_to raise_error
      end
    end

    context "when user is nil" do
      it "does not raise an error" do
        expect { described_class.call(nil) }.not_to raise_error
      end
    end
  end
end
