require "rails_helper"

RSpec.describe CpSubscription do
  describe "validations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:cp_payments).dependent(:destroy) }
    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "enums" do
    it {
      expect(described_class.statuses).to eq(
                                            "trial" => 0, "active" => 1, "halted" => 2, "cancelled" => 3, "expired" => 4,
                                            )
    }
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:active_sub) { create(:cp_subscription, user: user, status: :active) }
    let!(:trial_sub) { create(:cp_subscription, :trial, user: user) }
    let!(:cancelled_sub) { create(:cp_subscription, :cancelled, user: user) }

    describe ".current" do
      it "returns trial and active subscriptions only" do
        expect(described_class.current).to contain_exactly(active_sub, trial_sub)
      end
    end

    describe ".trials_expiring_before" do
      let!(:expired_trial) { create(:cp_subscription, :expired_trial, user: user) }

      it "returns trials that have expired" do
        expect(described_class.trials_expiring_before(Time.current)).to include(expired_trial)
        expect(described_class.trials_expiring_before(Time.current)).not_to include(trial_sub)
      end
    end
  end

  describe "#trial_expired?" do
    it "returns true when trial has passed its end date" do
      sub = build(:cp_subscription, :expired_trial)
      expect(sub.trial_expired?).to be true
    end

    it "returns false when trial is still active" do
      sub = build(:cp_subscription, :trial)
      expect(sub.trial_expired?).to be false
    end

    it "returns false for non-trial subscriptions" do
      sub = build(:cp_subscription, status: :active)
      expect(sub.trial_expired?).to be false
    end
  end

  describe "#display_status" do
    it "shows trial expiry date for trial subscriptions" do
      sub = build(:cp_subscription, :trial, trial_ends_at: Time.zone.parse("2026-07-01"))
      expect(sub.display_status).to include("Trial")
      expect(sub.display_status).to include("July 01, 2026")
    end

    it "shows humanized status for active subscriptions" do
      sub = build(:cp_subscription, status: :active)
      expect(sub.display_status).to eq("Active")
    end
  end
end
