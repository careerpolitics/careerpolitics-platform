module MockExams
  class RegenerateSectionWorker
    include Sidekiq::Job

    sidekiq_options queue: :low_priority, lock: :until_executing, on_conflict: :replace

    def perform(template_id, section_name, section_type, section_count, topics)
      return unless Ai::Base::DEFAULT_KEY.present?

      template = MockExamTemplate.find_by(id: template_id)
      return unless template

      # Determine which unpublished sets need this section regenerated
      unpublished_set_numbers = template.pool_questions
                                        .where(set_published: false)
                                        .where.not(pool_set: nil)
                                        .distinct
                                        .pluck(:pool_set)

      return if unpublished_set_numbers.empty?

      sets_count = unpublished_set_numbers.size

      Rails.logger.info(
        "MockExams::RegenerateSectionWorker: Regenerating '#{section_name}' for #{sets_count} sets " \
          "of template #{template_id}",
        )

      generator = Ai::MockExamQuestionGenerator.new(template)
      total_needed = section_count * sets_count

      questions_data = generator.send(
        :generate_section_questions,
        section_name: section_name,
        section_type: section_type || "knowledge",
        count: total_needed,
        topics: topics,
        )

      created = 0
      unpublished_set_numbers.each_with_index do |set_number, set_idx|
        start_idx = set_idx * section_count
        batch = questions_data[start_idx, section_count] || []
        next_position = template.set_questions(set_number).maximum(:position).to_i

        batch.each do |q_data|
          next_position += 1
          MockExamQuestion.create!(
            mock_exam_template: template,
            mock_exam_attempt: nil,
            pool_set: set_number,
            section_name: section_name,
            position: next_position,
            question_type: section_type || "knowledge",
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
              regenerated_section: true,
              pool_set: set_number,
            },
            )
          created += 1
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn("MockExams::RegenerateSectionWorker: Skipped invalid question — #{e.message}")
        end
      end

      Rails.logger.info(
        "MockExams::RegenerateSectionWorker: Complete — #{created} questions created for '#{section_name}'",
        )

      MockExams::TranslatePoolWorker.perform_async(template_id)
    end
  end
end
