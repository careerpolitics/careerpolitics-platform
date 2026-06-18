class CpPayment < ApplicationRecord
  belongs_to :cp_subscription
  belongs_to :user

  enum status: { captured: 0, refunded: 1, failed: 2 }

  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :razorpay_payment_id, uniqueness: true, allow_nil: true

  scope :successful, -> { captured }
  scope :recent_first, -> { order(paid_at: :desc) }

  def amount_display
    "#{currency} #{format('%.2f', amount_cents / 100.0)}"
  end
end
