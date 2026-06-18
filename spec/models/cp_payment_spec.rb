require "rails_helper"

RSpec.describe CpPayment do
  describe "validations" do
    it { is_expected.to belong_to(:cp_subscription) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to validate_presence_of(:amount_cents) }
  end

  describe "enums" do
    it {
      expect(described_class.statuses).to eq(
                                            "captured" => 0, "refunded" => 1, "failed" => 2,
                                            )
    }
  end

  describe "#amount_display" do
    it "formats amount in currency" do
      payment = build(:cp_payment, amount_cents: 49900, currency: "INR")
      expect(payment.amount_display).to eq("INR 499.00")
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:sub) { create(:cp_subscription, user: user) }

    describe ".successful" do
      let!(:captured) { create(:cp_payment, cp_subscription: sub, user: user, status: :captured) }
      let!(:failed) { create(:cp_payment, :failed, cp_subscription: sub, user: user) }

      it "returns only captured payments" do
        expect(described_class.successful).to contain_exactly(captured)
      end
    end
  end
end
