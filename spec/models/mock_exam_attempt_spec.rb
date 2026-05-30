require "rails_helper"

RSpec.describe MockExamAttempt, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:expires_at) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:mock_exam_template) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:mock_exam_responses).dependent(:destroy) }
    it { is_expected.to have_many(:mock_exam_questions).dependent(:nullify) }
  end

  describe "daily attempt limit" do
    let(:user) { create(:user) }
    let(:template) { create(:mock_exam_template) }

    it "allows up to MAX_DAILY_ATTEMPTS_PER_TEMPLATE attempts" do
      described_class::MAX_DAILY_ATTEMPTS_PER_TEMPLATE.times do
        create(:mock_exam_attempt, user: user, mock_exam_template: template)
      end

      attempt = build(:mock_exam_attempt, user: user, mock_exam_template: template)
      expect(attempt).not_to be_valid
      expect(attempt.errors[:base].first).to include("Maximum")
    end

    it "resets the count daily" do
      described_class::MAX_DAILY_ATTEMPTS_PER_TEMPLATE.times do
        create(:mock_exam_attempt, user: user, mock_exam_template: template,
               created_at: 1.day.ago)
      end

      attempt = build(:mock_exam_attempt, user: user, mock_exam_template: template)
      expect(attempt).to be_valid
    end
  end

  describe "#expired?" do
    it "returns true when expires_at is in the past" do
      attempt = build(:mock_exam_attempt, expires_at: 1.minute.ago)
      expect(attempt.expired?).to be(true)
    end

    it "returns false when expires_at is in the future" do
      attempt = build(:mock_exam_attempt, expires_at: 30.minutes.from_now)
      expect(attempt.expired?).to be(false)
    end
  end

  describe "#time_remaining_seconds" do
    it "returns positive seconds when time is left" do
      attempt = build(:mock_exam_attempt, expires_at: 10.minutes.from_now)
      expect(attempt.time_remaining_seconds).to be_between(590, 600)
    end

    it "returns 0 when expired" do
      attempt = build(:mock_exam_attempt, expires_at: 1.minute.ago)
      expect(attempt.time_remaining_seconds).to eq(0)
    end

    it "returns 0 when submitted" do
      attempt = build(:mock_exam_attempt, :submitted, expires_at: 10.minutes.from_now)
      expect(attempt.time_remaining_seconds).to eq(0)
    end
  end
end
