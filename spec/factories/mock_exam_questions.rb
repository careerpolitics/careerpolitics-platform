FactoryBot.define do
  factory :mock_exam_question do
    mock_exam_template
    mock_exam_attempt { nil }
    section_name { "General Knowledge" }
    sequence(:position) { |n| n }
    question_type { :knowledge }
    question_text { Faker::Lorem.question }
    question_format { :text }
    options do
      [
        { "key" => "A", "text" => Faker::Lorem.sentence },
        { "key" => "B", "text" => Faker::Lorem.sentence },
        { "key" => "C", "text" => Faker::Lorem.sentence },
        { "key" => "D", "text" => Faker::Lorem.sentence },
      ]
    end
    correct_option_key { %w[A B C D].sample }
    explanation { Faker::Lorem.paragraph }
    difficulty { :medium }
    topic_tags { [Faker::Lorem.word] }

    trait :easy do
      difficulty { :easy }
    end

    trait :hard do
      difficulty { :hard }
    end

    trait :maths do
      question_type { :maths }
      section_name { "Quantitative Aptitude" }
      solution_steps { "Step 1: ...\nStep 2: ...\nAnswer: Option B" }
    end

    trait :pool do
      mock_exam_attempt { nil }
    end

    trait :with_hindi do
      text_hi { "हिंदी प्रश्न पाठ" }
      explanation_hi { "हिंदी व्याख्या" }
    end
  end
end
