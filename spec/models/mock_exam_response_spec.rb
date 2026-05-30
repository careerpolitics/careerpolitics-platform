require "rails_helper"

RSpec.describe MockExamResponse, type: :model do
  describe "validations" do
    it { is_expected.to validate_inclusion_of(:selected_option_key).in_array(%w[A B C D]).allow_nil }
  end

  describe "associations" do
    it { is_expected.to belong_to(:mock_exam_attempt) }
    it { is_expected.to belong_to(:mock_exam_question) }
  end

  describe "#answered?" do
    it "returns true when an option is selected" do
      response = build(:mock_exam_response, selected_option_key: "B")
      expect(response.answered?).to be(true)
    end

    it "returns false when no option is selected" do
      response = build(:mock_exam_response, :unanswered)
      expect(response.answered?).to be(false)
    end
  end

  describe "#evaluate!" do
    let(:question) { create(:mock_exam_question, correct_option_key: "B") }
    let(:attempt) { create(:mock_exam_attempt, mock_exam_template: question.mock_exam_template) }

    it "marks correct when selected matches correct_option_key" do
      response = create(:mock_exam_response, mock_exam_attempt: attempt,
                        mock_exam_question: question,
                        selected_option_key: "B")
      response.evaluate!
      expect(response.is_correct).to be(true)
    end

    it "marks incorrect when selected does not match" do
      response = create(:mock_exam_response, mock_exam_attempt: attempt,
                        mock_exam_question: question,
                        selected_option_key: "C")
      response.evaluate!
      expect(response.is_correct).to be(false)
    end

    it "does nothing for unanswered responses" do
      response = create(:mock_exam_response, mock_exam_attempt: attempt,
                        mock_exam_question: question,
                        selected_option_key: nil)
      response.evaluate!
      expect(response.is_correct).to be_nil
    end
  end
end
