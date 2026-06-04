module MockExams
  class GeneratePoolWorker
    include Sidekiq::Job

    sidekiq_options queue: :low_priority, lock: :until_executing, on_conflict: :replace

    def perform(template_id, sets_count = 3)
      return unless Ai::Base::DEFAULT_KEY.present?

      template = MockExamTemplate.find_by(id: template_id)
      return unless template

      Rails.logger.info("MockExams::GeneratePoolWorker: Starting pool generation for template #{template_id}")

      next_set = (template.pool_questions.maximum(:pool_set) || 0) + 1
      sections_config = template.sections_config

      generator = Ai::MockExamQuestionGenerator.new(template)
      questions_data = generator.generate_pool(sets_count: sets_count)

      # Group generated questions by section_name
      questions_by_section = questions_data.group_by { |q| q["section_name"] }

      # Build each set with the exact section counts from sections_config
      sets = Array.new(sets_count) { [] }
      sections_config.each do |section|
        section_name = section["name"]
        section_count = section["count"]
        available = questions_by_section[section_name] || []

        sets_count.times do |set_idx|
          start_idx = set_idx * section_count
          batch = available[start_idx, section_count] || []
          sets[set_idx].concat(batch)
        end
      end

      created = 0
      sets.each_with_index do |set_questions, set_idx|
        set_number = next_set + set_idx

        set_questions.each_with_index do |q_data, pos|
          MockExamQuestion.create!(
            mock_exam_template: template,
            mock_exam_attempt: nil,
            pool_set: set_number,
            section_name: q_data["section_name"],
            position: pos + 1,
            question_type: q_data["question_type"] || "knowledge",
            question_text: q_data["question_text"],
            question_format: :text,
            options: q_data["options"],
            correct_option_key: q_data["correct_option_key"],
            explanation: q_data["explanation"],
            solution_steps: q_data["solution_steps"],
            difficulty: q_data["difficulty"] || "medium",
            topic_tags: q_data["topic_tags"] || [],
            ai_generation_metadata: {
              model: Ai::Base::DEFAULT_LITE_MODEL,
              generated_at: Time.current.iso8601,
              pool_generation: true,
              pool_set: set_number,
            },
            )
          created += 1
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn("MockExams::GeneratePoolWorker: Skipped invalid question — #{e.message}")
        end
      end

      Rails.logger.info(
        "MockExams::GeneratePoolWorker: Pool complete — #{created} questions created for template #{template_id}",
        )

      MockExams::TranslatePoolWorker.perform_async(template_id)
    end
  end
end
