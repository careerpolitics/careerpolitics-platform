FactoryBot.define do
  factory :mock_exam_template do
    title { "#{Faker::Lorem.sentence(word_count: 3)} Mock" }
    sequence(:slug) { |n| "mock-exam-#{n}-#{SecureRandom.hex(4)}" }
    description { Faker::Lorem.paragraph }
    exam_category { :upsc_prelims }
    total_questions { 10 }
    duration_minutes { 30 }
    marks_per_correct { 2.0 }
    negative_marks_per_wrong { 0.67 }
    question_display_mode { :one_at_a_time }
    difficulty_level { :mixed }
    sections_config do
      [
        { "name" => "General Knowledge", "count" => 5, "type" => "knowledge" },
        { "name" => "Current Affairs", "count" => 5, "type" => "knowledge" },
      ]
    end
    has_calculator { false }
    has_scratchpad { true }
    active { true }
    published { true }

    trait :with_maths do
      exam_category { :upsc_csat }
      has_calculator { true }
      sections_config do
        [
          { "name" => "Quantitative Aptitude", "count" => 5, "type" => "maths" },
          { "name" => "Logical Reasoning", "count" => 5, "type" => "reasoning" },
        ]
      end
    end

    trait :unpublished do
      published { false }
    end
  end
end
