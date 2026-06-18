class CreateCpPayments < ActiveRecord::Migration[7.0]
  def change
    create_table :cp_payments do |t|
      t.references :cp_subscription, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.string :razorpay_payment_id, index: { unique: true, where: "razorpay_payment_id IS NOT NULL" }
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "INR"
      t.string :method_type # upi, card, netbanking, wallet
      t.integer :status, null: false, default: 0 # enum: captured, refunded, failed
      t.datetime :paid_at

      t.timestamps
    end

    add_index :cp_payments, :user_id
    add_index :cp_payments, :status
  end
end
