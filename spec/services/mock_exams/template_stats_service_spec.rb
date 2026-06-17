require "rails_helper"

RSpec.describe MockExams::TemplateStatsService do
  let(:template) do
    create(:mock_exam_template,
           total_questions: 5,
           marks_per_correct: 2.0,
           negative_marks_per_wrong: 0.67)
  end
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }

  describe "#call" do
    context "with no attempts" do
      subject(:result) { described_class.new(template).call }

      it "creates a stat record with zero defaults" do
        stat = result
        expect(stat).to be_persisted
        expect(stat.total_attempts).to eq(0)
        expect(stat.unique_users).to eq(0)
        expect(stat.average_score).to eq(0)
        expect(stat.median_score).to eq(0)
        expect(stat.highest_score).to eq(0)
        expect(stat.lowest_score).to eq(0)
        expect(stat.average_accuracy).to eq(0)
        expect(stat.completion_rate).to eq(0)
      end
    end

    context "with submitted attempts" do
      let!(:attempt1) do
        create(:mock_exam_attempt, :submitted,
               mock_exam_template: template,
               user: user1,
               total_score: 6.0,
               accuracy_percent: 60.0,
               started_at: 40.minutes.ago,
               submitted_at: 10.minutes.ago,
               section_scores: {
                 "Polity" => { "score" => 4.0, "correct" => 2, "incorrect" => 1 },
                 "History" => { "score" => 2.0, "correct" => 1, "incorrect" => 0 },
               })
      end

      let!(:attempt2) do
        create(:mock_exam_attempt, :submitted,
               mock_exam_template: template,
               user: user2,
               total_score: 8.0,
               accuracy_percent: 80.0,
               started_at: 35.minutes.ago,
               submitted_at: 10.minutes.ago,
               section_scores: {
                 "Polity" => { "score" => 6.0, "correct" => 3, "incorrect" => 0 },
                 "History" => { "score" => 2.0, "correct" => 1, "incorrect" => 1 },
               })
      end

      let!(:in_progress_attempt) do
        create(:mock_exam_attempt,
               mock_exam_template: template,
               user: user1,
               status: :in_progress)
      end

      subject(:result) { described_class.new(template).call }

      it "counts only submitted/timed_out attempts" do
        expect(result.total_attempts).to eq(2)
      end

      it "counts unique users" do
        expect(result.unique_users).to eq(2)
      end

      it "computes average_score" do
        expect(result.average_score).to eq(7.0)
      end

      it "computes median_score for even count" do
        expect(result.median_score).to eq(7.0)
      end

      it "computes highest and lowest score" do
        expect(result.highest_score).to eq(8.0)
        expect(result.lowest_score).to eq(6.0)
      end

      it "computes average_accuracy" do
        expect(result.average_accuracy).to eq(70.0)
      end

      it "computes completion_rate including in-progress" do
        # 2 completed out of 3 total started
        expect(result.completion_rate).to eq(66.7)
      end

      it "builds section_averages from section_scores" do
        sections = result.section_averages
        expect(sections).to have_key("Polity")
        expect(sections["Polity"][:avg_correct]).to eq(2.5)
        expect(sections).to have_key("History")
      end

      it "sets last_refreshed_at" do
        expect(result.last_refreshed_at).to be_within(5.seconds).of(Time.current)
      end

      it "updates existing stat record on re-run" do
        first_stat = described_class.new(template).call
        second_stat = described_class.new(template).call
        expect(first_stat.id).to eq(second_stat.id)
      end
    end

    context "with a single attempt (odd median)" do
      let!(:solo_attempt) do
        create(:mock_exam_attempt, :submitted,
               mock_exam_template: template,
               user: user1,
               total_score: 5.33,
               accuracy_percent: 53.3,
               started_at: 30.minutes.ago,
               submitted_at: 10.minutes.ago,
               section_scores: {})
      end

      it "returns the single score as median" do
        stat = described_class.new(template).call
        expect(stat.median_score).to eq(5.33)
      end
    end

    context "with difficulty_accuracy" do
      let!(:attempt) do
        create(:mock_exam_attempt, :submitted,
               mock_exam_template: template,
               user: user1)
      end

      before do
        easy_q = create(:mock_exam_question,
                        mock_exam_template: template,
                        mock_exam_attempt: attempt,
                        difficulty: :easy,
                        position: 1,
                        correct_option_key: "A")
        hard_q = create(:mock_exam_question,
                        mock_exam_template: template,
                        mock_exam_attempt: attempt,
                        difficulty: :hard,
                        position: 2,
                        correct_option_key: "B")

        create(:mock_exam_response, :correct,
               mock_exam_attempt: attempt,
               mock_exam_question: easy_q,
               selected_option_key: "A")
        create(:mock_exam_response, :incorrect,
               mock_exam_attempt: attempt,
               mock_exam_question: hard_q,
               selected_option_key: "C")
      end

      it "computes per-difficulty accuracy" do
        stat = described_class.new(template).call
        expect(stat.difficulty_accuracy["easy"]).to eq(100.0)
        expect(stat.difficulty_accuracy["hard"]).to eq(0.0)
        expect(stat.difficulty_accuracy["medium"]).to eq(0)
      end
    end
  end
end
