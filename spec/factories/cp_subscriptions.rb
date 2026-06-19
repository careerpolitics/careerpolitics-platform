FactoryBot.define do
  factory :cp_subscription do
    user
    status { :active }
    provider { "razorpay" }
    razorpay_order_id { "order_#{SecureRandom.hex(8)}" }
    plan_type { "monthly" }
    amount_cents { 9900 }
    currency { "INR" }
    current_period_start { Time.current }
    current_period_end { 30.days.from_now }

    trait :yearly do
      plan_type { "yearly" }
      amount_cents { 99900 }
      current_period_end { 1.year.from_now }
    end

    trait :trial do
      status { :trial }
      razorpay_order_id { nil }
      plan_type { nil }
      amount_cents { 0 }
      trial_ends_at { 7.days.from_now }
      current_period_end { 7.days.from_now }
    end

    trait :expired_trial do
      status { :trial }
      razorpay_order_id { nil }
      plan_type { nil }
      amount_cents { 0 }
      trial_ends_at { 1.day.ago }
      current_period_end { 1.day.ago }
    end

    trait :cancelled do
      status { :cancelled }
      cancelled_at { Time.current }
    end
  end
end
