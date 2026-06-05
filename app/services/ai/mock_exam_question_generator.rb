module Ai
  class MockExamQuestionGenerator
    VERSION = "1.0"
    MAX_RETRIES = 2
    BATCH_SIZE = 20
    MAX_SHORTFALL_RETRIES = 3

    def initialize(template, ai_client: nil)
      @template = template
      @ai_client = ai_client || Ai::Base.new(
        model: Ai::Base::DEFAULT_LITE_MODEL, wrapper: self,
        )
    end

    def generate_pool(sets_count: 3)
      questions = []

      @template.sections_config.each do |section|
        section_count = section["count"] * sets_count
        section_questions = generate_section_questions(
          section_name: section["name"],
          section_type: section["type"] || "knowledge",
          count: section_count,
          topics: section["topics"],
          )
        questions.concat(section_questions)
      end

      questions
    end

    private

    def generate_section_questions(section_name:, section_type:, count:, topics: nil)
      all_questions = []
      remaining = count
      shortfall_retries = 0

      while remaining > 0 && shortfall_retries <= MAX_SHORTFALL_RETRIES
        batches = (remaining.to_f / BATCH_SIZE).ceil

        batches.times do |batch_index|
          batch_count = [BATCH_SIZE, remaining - (batch_index * BATCH_SIZE)].min
          prompt = build_prompt(
            section_name: section_name, section_type: section_type,
            count: batch_count, topics: topics,
            )

          parsed = generate_with_retry(prompt)
          if parsed
            parsed = sanitize_svg_questions(parsed) if section_type == "visual_reasoning"
            all_questions.concat(parsed)
          end
        end

        remaining = count - all_questions.size
        break if remaining <= 0

        shortfall_retries += 1
        Rails.logger.warn(
          "Ai::MockExamQuestionGenerator: Section '#{section_name}' shortfall — " \
            "got #{all_questions.size}/#{count}, retry #{shortfall_retries}/#{MAX_SHORTFALL_RETRIES} " \
            "for #{remaining} more",
          )
      end

      if all_questions.size < count
        Rails.logger.error(
          "Ai::MockExamQuestionGenerator: Section '#{section_name}' incomplete — " \
            "#{all_questions.size}/#{count} after all retries",
          )
      end

      all_questions
    end

    def sanitize_svg_questions(questions)
      questions.map do |q|
        q["question_svg"] = MockExams::SvgSanitizer.sanitize(q["question_svg"]) if q["question_svg"].present?
        q["options"] = MockExams::SvgSanitizer.sanitize_options(q["options"]) if q["options"].is_a?(Array)
        q["question_format"] = "svg" if q["question_svg"].present?
        q
      end
    end

    def generate_with_retry(prompt)
      retries = 0
      begin
        response = @ai_client.call(prompt, response_mime_type: "application/json")
        cleaned = clean_json_response(response)
        parsed = JSON.parse(cleaned)

        unless parsed.is_a?(Array)
          raise "Response is not a JSON array"
        end

        # Keep valid questions, filter out malformed ones instead of rejecting the whole batch
        valid, invalid = parsed.partition { |q| valid_question?(q) }

        if invalid.any?
          Rails.logger.warn(
            "Ai::MockExamQuestionGenerator: Filtered #{invalid.length} malformed questions " \
              "from batch of #{parsed.length}",
            )
        end

        raise "No valid questions in response" if valid.empty?

        valid
      rescue StandardError => e
        retries += 1
        if retries <= MAX_RETRIES
          Rails.logger.warn(
            "Ai::MockExamQuestionGenerator: Retry #{retries}/#{MAX_RETRIES} — #{e.message}",
            )
          retry
        end
        Rails.logger.error(
          "Ai::MockExamQuestionGenerator: Failed after #{MAX_RETRIES} retries — #{e.message}",
          )
        nil
      end
    end

    def build_prompt(section_name:, section_type:, count:, topics: nil)
      case section_type
      when "maths", "reasoning", "data_interp"
        build_maths_reasoning_prompt(section_name: section_name, section_type: section_type,
                                     count: count, topics: topics)
      when "visual_reasoning"
        build_visual_reasoning_prompt(section_name: section_name, count: count, topics: topics)
      else
        build_knowledge_prompt(section_name: section_name, count: count, topics: topics)
      end
    end

    def build_knowledge_prompt(section_name:, count:, topics: nil)
      topics_line = topics.present? ? "Topics: #{Array(topics).join(', ')}" : ""

      <<~PROMPT
        You are an expert exam question creator for Indian competitive examinations.
        Generate #{count} multiple-choice questions for this section:

        Exam type: #{@template.exam_category}
        Section: #{section_name}
        Difficulty: #{@template.difficulty_level}
        #{topics_line}
        #{@template.ai_prompt_context}

        Return a JSON array where each item has:
        - section_name (string), question_type (string: "knowledge"),
          question_text (string), options (array of {key: "A"/"B"/"C"/"D", text: "..."}),
          correct_option_key (string: "A"/"B"/"C"/"D"), explanation (string),
          difficulty (string: "easy"/"medium"/"hard"), topic_tags (array of strings)

        Requirements:
        - Each question must have exactly 4 options (A, B, C, D)
        - Questions must be factually accurate
        - Explanations should be concise but informative
        - Vary difficulty within the specified range
        - Generate in ENGLISH ONLY
      PROMPT
    end

    def build_maths_reasoning_prompt(section_name:, section_type:, count:, topics: nil)
      topics_line = topics.present? ? "Topics: #{Array(topics).join(', ')}" : ""
      subtypes_line = section_subtypes(section_type)

      <<~PROMPT
        You are an expert exam question creator for Indian competitive examinations.
        Generate #{count} #{section_type} multiple-choice questions.

        Section: #{section_name}
        Type: #{section_type}
        Difficulty: #{@template.difficulty_level}
        #{topics_line}
        #{subtypes_line}
        #{@template.ai_prompt_context}

        Return a JSON array where each item has:
        - section_name (string), question_type (string: "#{section_type}"),
          question_text (string, use LaTeX notation $...$ for math),
          options (array of {key: "A"/"B"/"C"/"D", text: "..."}),
          correct_option_key (string), explanation (string),
          solution_steps (string: detailed step-by-step solving with LaTeX $...$ for math expressions),
          difficulty (string: "easy"/"medium"/"hard"), topic_tags (array of strings)

        Requirements:
        - Each question MUST have exactly 4 options (A, B, C, D)
        - Use $ delimiters for inline math and $$ for display math
        - The correct answer MUST be computationally verifiable from solution_steps
        - solution_steps must show complete working with intermediate calculations
        - Vary question subtypes across the batch
        - Generate in ENGLISH ONLY
      PROMPT
    end

    def build_visual_reasoning_prompt(section_name:, count:, topics: nil)
      topics_line = topics.present? ? "Topics: #{Array(topics).join(', ')}" : ""

      <<~PROMPT
        You are an expert exam question creator for Indian competitive examinations.
        Generate #{count} visual reasoning multiple-choice questions with inline SVG figures.

        Section: #{section_name}
        Difficulty: #{@template.difficulty_level}
        #{topics_line}
        #{@template.ai_prompt_context}

        Question types to include (vary across the batch):
        - Figure series: Pattern of shapes with progressive transformation (rotation, scaling, addition)
        - Mirror/water image: An original figure, options are candidate reflections
        - Paper folding & cutting: Show fold sequence + cut, options show unfolded results
        - Embedded figures: A complex figure with a simpler figure hidden inside
        - Venn diagrams: Overlapping circles representing sets, questions about intersections
        - Pattern completion: A grid/matrix with a missing cell

        Return a JSON array where each item has:
        - section_name (string), question_type (string: "visual_reasoning"),
          question_text (string: brief instruction like "Find the next figure in the series"),
          question_svg (string: complete inline SVG markup for the question figure),
          options (array of {key: "A"/"B"/"C"/"D", text: "Option A", svg: "<svg>...</svg>"}),
          correct_option_key (string), explanation (string),
          difficulty (string), topic_tags (array of strings)

        SVG Requirements:
        - Each SVG MUST have viewBox="0 0 200 200" and width="200" height="200"
        - Use ONLY basic SVG elements: rect, circle, ellipse, line, polyline, polygon, path, text, g
        - Use simple fills and strokes: black, white, #333, #666, #999, #ccc, none
        - NO external references, NO embedded images, NO <script> tags
        - Keep figures simple and clear — geometric shapes only
        - Option SVGs should use viewBox="0 0 100 100" width="100" height="100"
        - Generate in ENGLISH ONLY
      PROMPT
    end

    def section_subtypes(section_type)
      case section_type
      when "maths"
        "Question subtypes to include: Arithmetic (percentages, profit-loss, SI/CI, ratio-proportion, " \
          "time-work-speed), Algebra (equations, inequalities, progressions), Number System (divisibility, " \
          "HCF/LCM, remainders), Geometry (triangles, circles, coordinate geometry), Mensuration (areas, " \
          "volumes, surface areas), Trigonometry, Data Interpretation (tables, bar/pie charts)."
      when "reasoning"
        "Question subtypes to include: Analogies, Number/Letter Series, Coding-Decoding, Syllogisms, " \
          "Blood Relations, Seating Arrangements (linear/circular), Direction Sense, Ranking & Order, " \
          "Calendar & Clock problems, Statement-Conclusion, Input-Output."
      when "data_interp"
        "Question subtypes to include: Data tables, Bar charts (described textually), Pie charts " \
          "(described textually), Line graphs (described textually), Mixed data sets. " \
          "Present data clearly in the question_text using formatted tables or descriptions. " \
          "Questions should require calculation from the given data."
      else
        ""
      end
    end

    def clean_json_response(response)
      text = response.to_s.strip

      # Remove markdown code fences if present
      text = text.gsub(/\A```

(?:json)?\s*\n?/, "").gsub(/\n?

```\s*\z/, "").strip

      return text unless text.include?("[")

      # Fast path: try parsing as-is
      begin
        JSON.parse(text)
        return text
      rescue JSON::ParserError
        # Continue with cleaning
      end

      # Trim from the last ] backwards to find a valid JSON array
      start_idx = text.index("[")
      last_bracket = text.rindex("]")
      while last_bracket && last_bracket > start_idx
        candidate = text[start_idx..last_bracket]
        begin
          JSON.parse(candidate)
          return candidate
        rescue JSON::ParserError
          last_bracket = text.rindex("]", last_bracket - 1)
        end
      end

      # No valid closing ] — try to salvage a truncated response
      truncated = text[start_idx..]
      last_brace = truncated.rindex("}")
      if last_brace
        salvaged = truncated[0..last_brace].sub(/,\s*\z/, "") + "]"
        begin
          JSON.parse(salvaged)
          return salvaged
        rescue JSON::ParserError
          # Fall through — will fail in caller and trigger retry
        end
      end

      text
    end

    def valid_question?(question)
      question.is_a?(Hash) &&
        question["question_text"].present? &&
        question["options"].is_a?(Array) &&
        question["options"].length == 4 &&
        question["correct_option_key"].present? &&
        %w[A B C D].include?(question["correct_option_key"])
    end
  end
end
