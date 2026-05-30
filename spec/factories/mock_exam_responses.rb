FactoryBot.define do
  factory :mock_exam_response do
    mock_exam_attempt
    mock_exam_question
    selected_option_key { "A" }
    marked_for_review { false }
    time_spent_seconds { rand(10..120) }

    trait :correct do
      is_correct { true }
    end

    trait :incorrect do
      is_correct { false }
    end

    trait :unanswered do
      selected_option_key { nil }
      is_correct { nil }
    end

    trait :reviewed do
      marked_for_review { true }
    end
  end
end
