FactoryBot.define do
  factory :cp_subscription do
    user
    status { :active }
    provider { "razorpay" }
    razorpay_subscription_id { "sub_#{SecureRandom.hex(8)}" }
    razorpay_plan_id { "plan_test123" }
    current_period_start { Time.current }
    current_period_end { 30.days.from_now }

    trait :trial do
      status { :trial }
      razorpay_subscription_id { nil }
      razorpay_plan_id { nil }
      trial_ends_at { 7.days.from_now }
      current_period_end { 7.days.from_now }
    end

    trait :expired_trial do
      status { :trial }
      razorpay_subscription_id { nil }
      razorpay_plan_id { nil }
      trial_ends_at { 1.day.ago }
      current_period_end { 1.day.ago }
    end

    trait :halted do
      status { :halted }
    end

    trait :cancelled do
      status { :cancelled }
      cancelled_at { Time.current }
    end
  end
end
