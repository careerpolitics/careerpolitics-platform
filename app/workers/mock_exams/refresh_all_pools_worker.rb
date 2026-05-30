module MockExams
  class RefreshAllPoolsWorker
    include Sidekiq::Job

    sidekiq_options queue: :low_priority, lock: :until_executing, on_conflict: :replace

    def perform
      return unless Ai::Base::DEFAULT_KEY.present?

      templates = MockExamTemplate.active_published
      Rails.logger.info("MockExams::RefreshAllPoolsWorker: Refreshing pools for #{templates.count} templates")

      templates.find_each do |template|
        MockExams::GeneratePoolWorker.perform_async(template.id)
      end
    end
  end
end
