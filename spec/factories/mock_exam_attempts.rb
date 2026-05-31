FactoryBot.define do
  factory :mock_exam_attempt do
    mock_exam_template
    user
    status { :in_progress }
    started_at { Time.current }
    expires_at { Time.current + 30.minutes }

    trait :submitted do
      status { :submitted }
      submitted_at { Time.current }
      total_score { 14.0 }
      max_possible_score { 20.0 }
      correct_count { 8 }
      incorrect_count { 1 }
      unanswered_count { 1 }
      accuracy_percent { 80.0 }
      percentile { 65.0 }
      rank { 5 }
    end

    trait :timed_out do
      status { :timed_out }
      submitted_at { Time.current }
    end

    trait :abandoned do
      status { :abandoned }
    end
  end
end
