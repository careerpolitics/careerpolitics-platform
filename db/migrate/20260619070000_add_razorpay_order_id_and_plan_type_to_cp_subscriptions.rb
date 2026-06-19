class AddRazorpayOrderIdAndPlanTypeToCpSubscriptions < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column :cp_subscriptions, :razorpay_order_id, :string
    add_column :cp_subscriptions, :plan_type, :string

    add_index :cp_subscriptions, :razorpay_order_id, unique: true,
              where: "razorpay_order_id IS NOT NULL",
              name: "index_cp_subscriptions_on_razorpay_order_id",
              algorithm: :concurrently
  end
end
