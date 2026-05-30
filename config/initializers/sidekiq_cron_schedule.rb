# frozen_string_literal: true

if defined?(Sidekiq::Cron)
  Sidekiq.configure_server do |_config|
    Sidekiq::Cron::Job.load_from_hash(
      "mock_exams_refresh_all_pools" => {
        "class" => "MockExams::RefreshAllPoolsWorker",
        "cron" => "0 3 * * 0", # Every Sunday at 3:00 AM UTC
        "queue" => "low_priority",
        "description" => "Refreshes question pools for all active mock exam templates weekly",
      },
      )
  end
end
