FactoryBot.define do
  factory :job_post do
    association :user
    sequence(:title) { |n| "Government Job Update #{n}" }
    sequence(:slug) { |n| "government-job-update-#{n}" }
    post_type { "new_update" }
    link { "/jobs/test-application" }
    published { true }
    approved { true }
    published_at { Time.current }
    featured { false }
    position { 0 }
  end
end
