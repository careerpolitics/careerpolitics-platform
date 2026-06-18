class RenameStripeIdCodeToRazorpaySubscriptionId < ActiveRecord::Migration[7.0]
  def change
    safety_assured { rename_column :users, :stripe_id_code, :razorpay_subscription_id }
  end
end
