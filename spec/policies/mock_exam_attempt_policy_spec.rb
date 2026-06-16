require "rails_helper"

RSpec.describe MockExamAttemptPolicy, type: :policy do
  subject { described_class.new(user, MockExamAttempt) }

  context "when user is not signed in" do
    let(:user) { nil }

    it { within_block_is_expected.to raise_error(Pundit::NotAuthorizedError) }
  end

  context "when user is signed in" do
    let(:user) { create(:user) }

    context "when user has no attempts today" do
      it { is_expected.to permit_actions(%i[create]) }
    end

    context "when user has used their daily free attempt" do
      before do
        template = create(:mock_exam_template)
        create(:mock_exam_attempt, user: user, mock_exam_template: template, created_at: Time.current)
      end

      it { is_expected.to forbid_actions(%i[create]) }
    end

    context "when user is a premium subscriber" do
      before do
        user.add_role("base_subscriber")
      end

      it { is_expected.to permit_actions(%i[create]) }

      context "when they have already used multiple attempts today" do
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

    context "when user is a premium subscriber" do
      before { user.add_role("base_subscriber") }

      it "returns nil" do
        expect(policy.daily_attempts_remaining).to be_nil
      end
    end

    context "when user has no attempts today" do
      it "returns the daily free limit" do
        expect(policy.daily_attempts_remaining).to eq(described_class::DAILY_FREE_LIMIT)
      end
    end

    context "when user has used their daily free attempt" do
      before do
        template = create(:mock_exam_template)
        create(:mock_exam_attempt, user: user, mock_exam_template: template, created_at: Time.current)
      end

      it "returns 0" do
        expect(policy.daily_attempts_remaining).to eq(0)
      end
    end

    context "when user's attempts were from yesterday" do
      before do
        template = create(:mock_exam_template)
        create(:mock_exam_attempt, user: user, mock_exam_template: template, created_at: 1.day.ago)
      end

      it "returns the daily free limit (resets daily)" do
        expect(policy.daily_attempts_remaining).to eq(described_class::DAILY_FREE_LIMIT)
      end
    end
  end
end
