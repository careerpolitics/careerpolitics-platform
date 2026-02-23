FactoryBot.define do
  factory :job_post do
    association :user
    sequence(:title) { |n| "Job Post #{n}" }
    post_type { "new_update" }
    link { "/jobs/sample-link" }
    published { true }
    approved { true }
  end
end
