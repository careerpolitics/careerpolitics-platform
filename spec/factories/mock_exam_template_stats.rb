FactoryBot.define do
  factory :mock_exam_template_stat do
    mock_exam_template
    total_attempts { 50 }
    unique_users { 40 }
    average_score { 12.5 }
    median_score { 11.0 }
    highest_score { 20.0 }
    lowest_score { 2.0 }
    average_accuracy { 62.5 }
    average_time_seconds { 1200 }
    score_distribution { [] }
    section_averages { {} }
    difficulty_accuracy { { "easy" => 82.0, "medium" => 60.0, "hard" => 35.0 } }
    completion_rate { 87.5 }
    last_refreshed_at { Time.current }
  end
end
