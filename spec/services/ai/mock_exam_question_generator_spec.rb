require "rails_helper"

RSpec.describe Ai::MockExamQuestionGenerator do
  let(:template) do
    create(:mock_exam_template,
           total_questions: 10,
           exam_category: :upsc_prelims,
           difficulty_level: :mixed,
           sections_config: [
             { "name" => "Polity", "count" => 5, "type" => "knowledge", "topics" => ["Constitution"] },
             { "name" => "History", "count" => 5, "type" => "knowledge", "topics" => ["Modern India"] },
           ],
           ai_prompt_context: "Focus on UPSC CSE syllabus")
  end

  let(:ai_client) { instance_double(Ai::Base) }

  subject(:generator) { described_class.new(template, ai_client: ai_client) }

  let(:valid_questions_json) do
    5.times.map do |i|
      {
        "section_name" => "Polity",
        "question_type" => "knowledge",
        "question_text" => "What is Article #{i + 1}?",
        "options" => [
          { "key" => "A", "text" => "Option A" },
          { "key" => "B", "text" => "Option B" },
          { "key" => "C", "text" => "Option C" },
          { "key" => "D", "text" => "Option D" },
        ],
        "correct_option_key" => "B",
        "explanation" => "Article #{i + 1} deals with...",
        "difficulty" => "medium",
        "topic_tags" => ["constitution"],
      }
    end.to_json
  end

  describe "#generate_pool" do
    before do
      allow(ai_client).to receive(:call).and_return(valid_questions_json)
    end

    it "generates multiplier * total_questions questions" do
      result = generator.generate_pool(multiplier: 2)
      expect(result).to be_an(Array)
      expect(result).to all(satisfy { |q| q["question_text"].present? })
    end

    it "calls the AI client with English-only prompt" do
      generator.generate_pool(multiplier: 1)
      expect(ai_client).to have_received(:call).at_least(:once) do |prompt, **_opts|
        expect(prompt).to include("ENGLISH ONLY")
      end
    end

    it "uses JSON response_mime_type" do
      generator.generate_pool(multiplier: 1)
      expect(ai_client).to have_received(:call)
                             .with(anything, response_mime_type: "application/json")
                             .at_least(:once)
    end
  end

  describe "maths/reasoning prompt generation" do
    let(:maths_template) do
      create(:mock_exam_template, :with_maths,
             total_questions: 10,
             sections_config: [
               { "name" => "Quantitative Aptitude", "count" => 5, "type" => "maths" },
               { "name" => "Logical Reasoning", "count" => 5, "type" => "reasoning" },
             ])
    end

    let(:maths_generator) { described_class.new(maths_template, ai_client: ai_client) }

    let(:maths_questions_json) do
      5.times.map do |i|
        {
          "section_name" => "Quantitative Aptitude",
          "question_type" => "maths",
          "question_text" => "If $x + #{i + 1} = 10$, find $x$.",
          "options" => [
            { "key" => "A", "text" => "$#{9 - i}$" },
            { "key" => "B", "text" => "$#{8 - i}$" },
            { "key" => "C", "text" => "$#{7 - i}$" },
            { "key" => "D", "text" => "$#{6 - i}$" },
          ],
          "correct_option_key" => "A",
          "explanation" => "Subtract #{i + 1} from both sides",
          "solution_steps" => "Step 1: $x + #{i + 1} = 10$\nStep 2: $x = 10 - #{i + 1} = #{9 - i}$",
          "difficulty" => "easy",
          "topic_tags" => ["algebra"],
        }
      end.to_json
    end

    before do
      allow(ai_client).to receive(:call).and_return(maths_questions_json)
    end

    it "uses maths-specific prompt with LaTeX instructions" do
      maths_generator.generate_pool(multiplier: 1)
      expect(ai_client).to have_received(:call).at_least(:once) do |prompt, **_opts|
        expect(prompt).to include("$ delimiters")
        expect(prompt).to include("solution_steps")
      end
    end

    it "includes section subtypes for maths" do
      maths_generator.generate_pool(multiplier: 1)
      expect(ai_client).to have_received(:call).at_least(:once) do |prompt, **_opts|
        if prompt.include?("maths")
          expect(prompt).to include("Arithmetic")
          expect(prompt).to include("Algebra")
        end
      end
    end

    it "includes section subtypes for reasoning" do
      maths_generator.generate_pool(multiplier: 1)
      expect(ai_client).to have_received(:call).at_least(:once) do |prompt, **_opts|
        if prompt.include?("reasoning")
          expect(prompt).to include("Analogies")
          expect(prompt).to include("Syllogisms")
        end
      end
    end

    it "generates solution_steps for maths questions" do
      result = maths_generator.generate_pool(multiplier: 1)
      maths_qs = result.select { |q| q["question_type"] == "maths" }
      expect(maths_qs).to all(satisfy { |q| q["solution_steps"].present? })
    end
  end

  describe "#section_subtypes" do
    subject(:generator_instance) { described_class.new(template, ai_client: ai_client) }

    it "returns maths subtypes" do
      result = generator_instance.send(:section_subtypes, "maths")
      expect(result).to include("Arithmetic", "Algebra", "Geometry", "Mensuration")
    end

    it "returns reasoning subtypes" do
      result = generator_instance.send(:section_subtypes, "reasoning")
      expect(result).to include("Analogies", "Coding-Decoding", "Syllogisms", "Blood Relations")
    end

    it "returns data_interp subtypes" do
      result = generator_instance.send(:section_subtypes, "data_interp")
      expect(result).to include("Data tables", "Bar charts")
    end

    it "returns empty string for unknown types" do
      result = generator_instance.send(:section_subtypes, "knowledge")
      expect(result).to eq("")
    end
  end

  describe "visual reasoning prompt generation" do
    let(:visual_template) do
      create(:mock_exam_template,
             total_questions: 5,
             sections_config: [
               { "name" => "Visual Reasoning", "count" => 5, "type" => "visual_reasoning" },
             ])
    end

    let(:visual_generator) { described_class.new(visual_template, ai_client: ai_client) }

    let(:visual_questions_json) do
      5.times.map do |i|
        {
          "section_name" => "Visual Reasoning",
          "question_type" => "visual_reasoning",
          "question_text" => "Find the next figure in the series",
          "question_svg" => '<svg viewBox="0 0 200 200" width="200" height="200"><circle cx="100" cy="100" r="50" fill="black"/></svg>',
          "options" => [
            { "key" => "A", "text" => "Option A", "svg" => '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="25"/></svg>' },
            { "key" => "B", "text" => "Option B", "svg" => '<svg viewBox="0 0 100 100"><rect width="50" height="50"/></svg>' },
            { "key" => "C", "text" => "Option C", "svg" => '<svg viewBox="0 0 100 100"><ellipse cx="50" cy="50" rx="40" ry="20"/></svg>' },
            { "key" => "D", "text" => "Option D", "svg" => '<svg viewBox="0 0 100 100"><polygon points="50,10 90,90 10,90"/></svg>' },
          ],
          "correct_option_key" => "A",
          "explanation" => "The pattern shows...",
          "difficulty" => "medium",
          "topic_tags" => ["figure_series"],
        }
      end.to_json
    end

    before do
      allow(ai_client).to receive(:call).and_return(visual_questions_json)
    end

    it "uses visual reasoning prompt with SVG instructions" do
      visual_generator.generate_pool(multiplier: 1)
      expect(ai_client).to have_received(:call).at_least(:once) do |prompt, **_opts|
        expect(prompt).to include("visual reasoning")
        expect(prompt).to include("SVG")
        expect(prompt).to include("viewBox")
      end
    end

    it "sanitizes SVG output in questions" do
      allow(MockExams::SvgSanitizer).to receive(:sanitize).and_call_original
      allow(MockExams::SvgSanitizer).to receive(:sanitize_options).and_call_original

      visual_generator.generate_pool(multiplier: 1)

      expect(MockExams::SvgSanitizer).to have_received(:sanitize).at_least(:once)
      expect(MockExams::SvgSanitizer).to have_received(:sanitize_options).at_least(:once)
    end

    it "sets question_format to svg for visual reasoning questions" do
      result = visual_generator.generate_pool(multiplier: 1)
      expect(result).to all(include("question_format" => "svg"))
    end

    it "strips dangerous SVG content from AI output" do
      malicious_json = [
        {
          "section_name" => "Visual Reasoning",
          "question_type" => "visual_reasoning",
          "question_text" => "Find the pattern",
          "question_svg" => '<svg viewBox="0 0 200 200"><script>alert("xss")</script><circle r="50"/></svg>',
          "options" => [
            { "key" => "A", "text" => "A", "svg" => '<svg viewBox="0 0 100 100"><rect width="50" height="50" onclick="evil()"/></svg>' },
            { "key" => "B", "text" => "B" },
            { "key" => "C", "text" => "C" },
            { "key" => "D", "text" => "D" },
          ],
          "correct_option_key" => "A",
          "explanation" => "Test",
          "difficulty" => "easy",
          "topic_tags" => [],
        },
      ].to_json

      allow(ai_client).to receive(:call).and_return(malicious_json)

      result = visual_generator.generate_pool(multiplier: 1)
      expect(result.first["question_svg"]).not_to include("<script")
      expect(result.first["options"].first["svg"]).not_to include("onclick")
    end
  end

  describe "retry logic" do
    it "retries up to MAX_RETRIES on malformed response" do
      call_count = 0
      allow(ai_client).to receive(:call) do
        call_count += 1
        if call_count <= 2
          "not valid json"
        else
          valid_questions_json
        end
      end

      result = generator.generate_pool(multiplier: 1)
      expect(result).to be_an(Array)
    end

    it "returns nil after exhausting retries" do
      allow(ai_client).to receive(:call).and_raise(StandardError.new("API down"))

      result = generator.generate_pool(multiplier: 1)
      expect(result).to eq([])
    end
  end
end
