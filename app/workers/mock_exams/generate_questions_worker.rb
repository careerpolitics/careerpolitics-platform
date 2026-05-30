module MockExams
  class GenerateQuestionsWorker
    include Sidekiq::Job

    sidekiq_options queue: :default, lock: :until_executing, on_conflict: :replace

    def perform(attempt_id)
      return unless Ai::Base::DEFAULT_KEY.present?

      attempt = MockExamAttempt.find_by(id: attempt_id)
      return unless attempt&.in_progress?

      template = attempt.mock_exam_template

      Rails.logger.info(
        "MockExams::GenerateQuestionsWorker: Generating fresh questions for attempt #{attempt_id}",
        )

      generator = Ai::MockExamQuestionGenerator.new(template)
      questions_data = generator.generate_for_attempt(attempt)

      created = 0
      questions_data.each_with_index do |q_data, idx|
        MockExamQuestion.create!(
          mock_exam_template: template,
          mock_exam_attempt: attempt,
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
            pool_generation: false,
          },
          )
        created += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("MockExams::GenerateQuestionsWorker: Skipped invalid question — #{e.message}")
      end

      Rails.logger.info(
        "MockExams::GenerateQuestionsWorker: Created #{created} questions for attempt #{attempt_id}",
        )
    end
  end
end
