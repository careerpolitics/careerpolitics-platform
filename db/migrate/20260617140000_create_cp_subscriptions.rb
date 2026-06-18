class CreateCpSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :cp_subscriptions do |t|
      t.references :user, null: false, foreign_key: true, index: false

      # Razorpay identifiers
      t.string :razorpay_subscription_id, index: { unique: true, where: "razorpay_subscription_id IS NOT NULL" }
      t.string :razorpay_plan_id
      t.string :razorpay_customer_id

      # Status tracking
      t.integer :status, null: false, default: 0 # enum: trial, active, halted, cancelled, expired
      t.string :provider, null: false, default: "razorpay" # razorpay, stripe, manual

      # Monetary
      t.integer :amount_cents
      t.string :currency, default: "INR"

      # Period tracking
      t.datetime :trial_ends_at
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :cp_subscriptions, :user_id
    add_index :cp_subscriptions, :status
    add_index :cp_subscriptions, :trial_ends_at, where: "status = 0" # trial status
  end
end
