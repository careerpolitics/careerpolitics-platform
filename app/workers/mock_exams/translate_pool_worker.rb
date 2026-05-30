module MockExams
  class TranslatePoolWorker
    include Sidekiq::Job

    sidekiq_options queue: :low_priority, lock: :until_executing, on_conflict: :replace

    def perform(template_id)
      return unless Ai::Base::DEFAULT_KEY.present?

      template = MockExamTemplate.find_by(id: template_id)
      return unless template

      translated = MockExams::TranslatePoolService.new(template).call

      Rails.logger.info(
        "MockExams::TranslatePoolWorker: Translated #{translated} questions for template #{template_id}",
        )
    end
  end
end
