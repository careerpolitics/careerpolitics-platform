require "rails_helper"

RSpec.describe MockExams::AssembleExamService do
  let(:template) do
    create(:mock_exam_template,
           total_questions: 4,
           sections_config: [
             { "name" => "Polity", "count" => 2, "type" => "knowledge" },
             { "name" => "History", "count" => 2, "type" => "knowledge" },
           ])
  end
  let(:user) { create(:user) }

  describe "#call" do
    context "when pool has enough unseen questions" do
      before do
        3.times { |i| create(:mock_exam_question, mock_exam_template: template, section_name: "Polity", position: i + 1) }
        3.times { |i| create(:mock_exam_question, mock_exam_template: template, section_name: "History", position: i + 4) }
      end

      it "returns questions from pool" do
        result = described_class.new(template, user).call
        expect(result).not_to be_nil
        expect(result.length).to eq(4)
      end

      it "returns questions from both sections" do
        result = described_class.new(template, user).call
        sections = result.map(&:section_name).uniq.sort
        expect(sections).to eq(%w[History Polity])
      end

      it "increments times_served on selected questions" do
        result = described_class.new(template, user).call
        result.each do |q|
          expect(q.reload.times_served).to eq(1)
        end
      end
    end

    context "when pool is empty" do
      it "returns nil" do
        result = described_class.new(template, user).call
        expect(result).to be_nil
      end
    end

    context "when user has seen questions" do
      before do
        2.times { |i| create(:mock_exam_question, mock_exam_template: template, section_name: "Polity", position: i + 1) }
        2.times { |i| create(:mock_exam_question, mock_exam_template: template, section_name: "History", position: i + 3) }
      end

      it "excludes previously seen questions" do
        # First attempt — sees all pool questions
        attempt = create(:mock_exam_attempt, mock_exam_template: template, user: user)
        template.pool_questions.each do |q|
          create(:mock_exam_response, mock_exam_attempt: attempt, mock_exam_question: q)
        end

        # Second attempt — pool is exhausted
        result = described_class.new(template, user).call
        expect(result).to be_nil
      end
    end
  end
end
