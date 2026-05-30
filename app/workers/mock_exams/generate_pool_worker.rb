module MockExams
  class GeneratePoolWorker
    include Sidekiq::Job

    sidekiq_options queue: :low_priority, lock: :until_executing, on_conflict: :replace

    def perform(template_id, multiplier = 5)
      return unless Ai::Base::DEFAULT_KEY.present?

      template = MockExamTemplate.find_by(id: template_id)
      return unless template

      Rails.logger.info("MockExams::GeneratePoolWorker: Starting pool generation for template #{template_id}")

      generator = Ai::MockExamQuestionGenerator.new(template)
      questions_data = generator.generate_pool(multiplier: multiplier)

      created = 0
      questions_data.each_with_index do |q_data, idx|
        MockExamQuestion.create!(
          mock_exam_template: template,
          mock_exam_attempt: nil,
          section_name: q_data["section_name"],
          position: idx + 1,
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
          },
          )
        created += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("MockExams::GeneratePoolWorker: Skipped invalid question — #{e.message}")
      end

      Rails.logger.info(
        "MockExams::GeneratePoolWorker: Pool complete — #{created} questions created for template #{template_id}",
        )

      MockExams::TranslatePoolWorker.perform_async(template_id)
    end
  end
end
