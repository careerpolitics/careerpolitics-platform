require "rails_helper"

RSpec.describe MockExamQuestion, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:section_name) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_presence_of(:question_text) }
    it { is_expected.to validate_presence_of(:correct_option_key) }
    it { is_expected.to validate_presence_of(:options) }
    it { is_expected.to validate_inclusion_of(:correct_option_key).in_array(%w[A B C D]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:mock_exam_template) }
    it { is_expected.to belong_to(:mock_exam_attempt).optional }
    it { is_expected.to have_many(:mock_exam_responses).dependent(:destroy) }
  end

  describe "options validation" do
    it "requires exactly 4 options" do
      question = build(:mock_exam_question, options: [{ "key" => "A", "text" => "foo" }])
      expect(question).not_to be_valid
      expect(question.errors[:options]).to include("must have exactly 4 entries")
    end

    it "accepts 4 options" do
      question = build(:mock_exam_question)
      expect(question).to be_valid
    end
  end

  describe "#pool_question?" do
    it "returns true when mock_exam_attempt_id is nil" do
      question = build(:mock_exam_question, mock_exam_attempt: nil)
      expect(question.pool_question?).to be(true)
    end

    it "returns false when linked to an attempt" do
      attempt = create(:mock_exam_attempt)
      question = build(:mock_exam_question, mock_exam_attempt: attempt)
      expect(question.pool_question?).to be(false)
    end
  end

  describe "#increment_served!" do
    it "increments times_served by 1" do
      question = create(:mock_exam_question)
      expect { question.increment_served! }.to change { question.reload.times_served }.by(1)
    end
  end

  describe "scopes" do
    let(:template) { create(:mock_exam_template) }

    it ".pool returns only pool questions" do
      create(:mock_exam_question, mock_exam_template: template, mock_exam_attempt: nil)
      attempt = create(:mock_exam_attempt, mock_exam_template: template)
      create(:mock_exam_question, mock_exam_template: template, mock_exam_attempt: attempt)

      expect(described_class.pool.count).to eq(1)
    end

    it ".for_section filters by section name" do
      create(:mock_exam_question, mock_exam_template: template, section_name: "Polity")
      create(:mock_exam_question, mock_exam_template: template, section_name: "History")

      expect(described_class.for_section("Polity").count).to eq(1)
    end
  end
end
