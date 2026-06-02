class MockExamAttempt < ApplicationRecord
  belongs_to :mock_exam_template
  belongs_to :user

  has_many :mock_exam_responses, dependent: :destroy
  has_many :mock_exam_questions, dependent: :nullify

  enum status: { in_progress: 0, submitted: 1, timed_out: 2, abandoned: 3 }

  validates :started_at, presence: true
  validates :expires_at, presence: true

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

end
