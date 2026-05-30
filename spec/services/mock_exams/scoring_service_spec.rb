require "rails_helper"

RSpec.describe MockExams::ScoringService do
  let(:template) do
    create(:mock_exam_template,
           total_questions: 5,
           marks_per_correct: 2.0,
           negative_marks_per_wrong: 0.67)
  end
  let(:user) { create(:user) }
  let(:attempt) do
    create(:mock_exam_attempt,
           mock_exam_template: template,
           user: user,
           status: :submitted,
           submitted_at: Time.current,
           time_per_question: { "1" => 30, "2" => 45, "3" => 20, "4" => 60, "5" => 15 })
  end

  before do
    5.times do |i|
      q = create(:mock_exam_question,
                 mock_exam_template: template,
                 mock_exam_attempt: attempt,
                 section_name: i < 3 ? "Polity" : "History",
                 position: i + 1,
                 correct_option_key: "B")

      selected = case i
                 when 0, 1, 2 then "B" # correct
                 when 3 then "C"        # wrong
                 when 4 then nil        # unanswered
                 end

      create(:mock_exam_response,
             mock_exam_attempt: attempt,
             mock_exam_question: q,
             selected_option_key: selected)
    end

    allow(MockExams::RefreshTemplateStatsWorker).to receive(:perform_async)
  end

  describe "#call" do
    subject(:result) { described_class.new(attempt).call }

    it "evaluates all responses" do
      result
      responses = attempt.mock_exam_responses.reload
      expect(responses.where(is_correct: true).count).to eq(3)
      expect(responses.where(is_correct: false).where.not(selected_option_key: nil).count).to eq(1)
    end

    it "computes correct score" do
      result
      expected_score = (3 * 2.0) - (1 * 0.67)
      expect(attempt.total_score).to eq(expected_score)
    end

    it "computes counts" do
      result
      expect(attempt.correct_count).to eq(3)
      expect(attempt.incorrect_count).to eq(1)
      expect(attempt.unanswered_count).to eq(1)
    end

    it "computes accuracy_percent" do
      result
      expect(attempt.accuracy_percent).to eq(60.0)
    end

    it "computes section_scores" do
      result
      expect(attempt.section_scores).to have_key("Polity")
      expect(attempt.section_scores["Polity"]["correct"]).to eq(3)
      expect(attempt.section_scores).to have_key("History")
    end

    it "computes percentile and rank" do
      result
      expect(attempt.percentile).to be_a(Numeric)
      expect(attempt.rank).to eq(1)
    end

    it "computes avg_time_per_question" do
      result
      expect(attempt.avg_time_per_question).to eq(34.0)
    end

    it "triggers stats refresh worker" do
      result
      expect(MockExams::RefreshTemplateStatsWorker).to have_received(:perform_async).with(template.id)
    end
  end
end
