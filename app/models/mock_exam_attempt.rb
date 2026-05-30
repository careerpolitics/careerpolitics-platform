class MockExamAttempt < ApplicationRecord
  MAX_DAILY_ATTEMPTS_PER_TEMPLATE = 3

  belongs_to :mock_exam_template
  belongs_to :user

  has_many :mock_exam_responses, dependent: :destroy
  has_many :mock_exam_questions, dependent: :nullify

  enum status: { in_progress: 0, submitted: 1, timed_out: 2, abandoned: 3 }
  enum questions_source: { pool: 0, generated: 1 }

  validates :started_at, presence: true
  validates :expires_at, presence: true
  validate :daily_attempt_limit, on: :create

  scope :submitted_or_timed_out, -> { where(status: %i[submitted timed_out]) }
  scope :for_template, ->(template) { where(mock_exam_template: template) }

  def expired?
    expires_at.present? && Time.current > expires_at
  end

  def time_remaining_seconds
    return 0 if expired? || submitted? || timed_out? || abandoned?

    [(expires_at - Time.current).to_i, 0].max
  end

  def total_questions
    mock_exam_template.total_questions
  end

  private

  def daily_attempt_limit
    return unless user && mock_exam_template

    today_count = user.mock_exam_attempts
                      .where(mock_exam_template: mock_exam_template)
                      .where("created_at >= ?", Time.current.beginning_of_day)
                      .count

    return unless today_count >= MAX_DAILY_ATTEMPTS_PER_TEMPLATE

    errors.add(:base, "Maximum #{MAX_DAILY_ATTEMPTS_PER_TEMPLATE} attempts per template per day")
  end
end
