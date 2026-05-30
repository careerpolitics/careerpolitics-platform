module MockExams
  class RefreshTemplateStatsWorker
    include Sidekiq::Job

    sidekiq_options queue: :low_priority, lock: :until_executing, on_conflict: :replace

    def perform(template_id)
      template = MockExamTemplate.find_by(id: template_id)
      return unless template

      MockExams::TemplateStatsService.new(template).call
    end
  end
end
