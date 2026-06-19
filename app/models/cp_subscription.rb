class CpSubscription < ApplicationRecord
  belongs_to :user
  has_many :cp_payments, dependent: :destroy

  enum status: { trial: 0, active: 1, halted: 2, cancelled: 3, expired: 4 }

  validates :provider, presence: true
  validates :status, presence: true
  validates :razorpay_order_id, uniqueness: true, allow_nil: true

  scope :current, -> { where(status: %i[trial active]) }
  scope :trials_expiring_before, ->(time) { trial.where("trial_ends_at <= ?", time) }

  def trial_expired?
    trial? && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  def display_status
    return "Trial (expires #{trial_ends_at.strftime('%B %d, %Y')})" if trial? && trial_ends_at.present?

    status.humanize
  end
end
