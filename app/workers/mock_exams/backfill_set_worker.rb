module MockExams
  class BackfillSetWorker
    include Sidekiq::Job

    sidekiq_options queue: :low_priority, lock: :until_executing, on_conflict: :replace

    def perform(template_id, set_number, shortfalls)
      return unless Ai::Base::DEFAULT_KEY.present?

      template = MockExamTemplate.find_by(id: template_id)
      return unless template

      Rails.logger.info(
        "MockExams::BackfillSetWorker: Backfilling set #{set_number} for template #{template_id} " \
          "(#{shortfalls.sum { |s| s['count'] }} questions needed)",
        )

      generator = Ai::MockExamQuestionGenerator.new(template)
      next_position = template.set_questions(set_number).maximum(:position).to_i

      created = 0
      shortfalls.each do |shortfall|
        section_questions = generator.send(
          :generate_section_questions,
          section_name: shortfall["name"],
          section_type: shortfall["type"] || "knowledge",
          count: shortfall["count"],
          topics: shortfall["topics"],
          )

        section_questions.each do |q_data|
          next_position += 1
          MockExamQuestion.create!(
            mock_exam_template: template,
            mock_exam_attempt: nil,
            pool_set: set_number,
            section_name: shortfall["name"],
            position: next_position,
            question_type: shortfall["type"] || "knowledge",
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
              backfill: true,
              pool_set: set_number,
            },
            )
          created += 1
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn("MockExams::BackfillSetWorker: Skipped invalid question — #{e.message}")
        end
      end

      Rails.logger.info(
        "MockExams::BackfillSetWorker: Backfill complete — #{created} questions added to set #{set_number}",
        )

      MockExams::TranslatePoolWorker.perform_async(template_id)
    end
  end
end
