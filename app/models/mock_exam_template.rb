class MockExamTemplate < ApplicationRecord
  belongs_to :subforem, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  has_many :mock_exam_questions, dependent: :destroy
  has_many :mock_exam_attempts, dependent: :destroy
  has_one :mock_exam_template_stat, dependent: :destroy

  enum exam_category: {
    upsc_prelims: 0,
    upsc_mains: 1,
    upsc_csat: 2,
    ssc_cgl: 3,
    ssc_chsl: 4,
    bank_po: 5,
    state_psc: 6,
    current_affairs: 7,
    custom: 8,
  }

  enum question_display_mode: { one_at_a_time: 0, all_at_once: 1 }
  enum difficulty_level: { easy: 0, medium: 1, hard: 2, mixed: 3 }

  validates :title, presence: true, length: { maximum: 200 }
  validates :slug, presence: true, uniqueness: true
  validates :total_questions, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :duration_minutes, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :marks_per_correct, presence: true, numericality: { greater_than: 0 }
  validates :negative_marks_per_wrong, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sections_config, presence: true

  before_validation :generate_slug, on: :create

  scope :active_published, -> { where(active: true, published: true) }
  scope :for_subforem, ->(subforem) { where(subforem_id: [subforem&.id, nil]) }

  def max_possible_score
    total_questions * marks_per_correct
  end

  def pool_questions
    mock_exam_questions.where(mock_exam_attempt_id: nil)
  end

  def pool_size
    pool_questions.count
  end

  def pool_ready?
    pool_size >= total_questions
  end

  private

  def generate_slug
    return if title.blank? || slug.present?

    self.slug = "#{title.parameterize}-#{SecureRandom.hex(4)}"
  end
end
