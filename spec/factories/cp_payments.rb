FactoryBot.define do
  factory :cp_payment do
    cp_subscription
    user { cp_subscription.user }
    razorpay_payment_id { "pay_#{SecureRandom.hex(8)}" }
    amount_cents { 49900 }
    currency { "INR" }
    status { :captured }
    paid_at { Time.current }

    trait :refunded do
      status { :refunded }
    end

    trait :failed do
      status { :failed }
    end
  end
end
