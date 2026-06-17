require "rails_helper"

RSpec.describe MockExamAttemptPolicy, type: :policy do
  subject { described_class.new(user, MockExamAttempt) }

  context "when user is not signed in" do
    let(:user) { nil }

    it { within_block_is_expected.to raise_error(Pundit::NotAuthorizedError) }
  end

  context "when user is signed in" do
    let(:user) { create(:user) }

    context "when user has no CP++ access" do
      it { is_expected.to forbid_actions(%i[create]) }
    end

    context "when user has an active free trial" do
      before do
        user.add_role("base_subscriber")
        user.update!(current_subscriber_status: :trial_subscription)
      end

      it { is_expected.to permit_actions(%i[create]) }

      context "when they have already used multiple attempts" do
        before do
          template = create(:mock_exam_template)
          3.times { create(:mock_exam_attempt, user: user, mock_exam_template: template, created_at: Time.current) }
        end

        it { is_expected.to permit_actions(%i[create]) }
      end
    end

    context "when user is a paying premium subscriber" do
      before do
        user.add_role("base_subscriber")
        user.update!(current_subscriber_status: :paying_subscription)
      end

      it { is_expected.to permit_actions(%i[create]) }

      context "when they have already used multiple attempts" do
        before do
          template = create(:mock_exam_template)
          3.times { create(:mock_exam_attempt, user: user, mock_exam_template: template, created_at: Time.current) }
        end

        it { is_expected.to permit_actions(%i[create]) }
      end
    end

    context "when user is suspended" do
      let(:user) { create(:user, :suspended) }

      it { within_block_is_expected.to raise_error(Pundit::NotAuthorizedError) }
    end
  end

  describe "#daily_attempts_remaining" do
    let(:user) { create(:user) }
    let(:policy) { described_class.new(user, MockExamAttempt) }

    context "when user has no CP++ access" do
      it "returns 0" do
        expect(policy.daily_attempts_remaining).to eq(0)
      end
    end

    context "when user has an active free trial" do
      before do
        user.add_role("base_subscriber")
        user.update!(current_subscriber_status: :trial_subscription)
      end

      it "returns nil for unlimited attempts" do
        expect(policy.daily_attempts_remaining).to be_nil
      end
    end

    context "when user is a paying premium subscriber" do
      before do
        user.add_role("base_subscriber")
        user.update!(current_subscriber_status: :paying_subscription)
      end

      it "returns nil for unlimited attempts" do
        expect(policy.daily_attempts_remaining).to be_nil
      end
    end
  end
end
