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
