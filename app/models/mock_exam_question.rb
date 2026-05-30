class MockExamQuestion < ApplicationRecord
  belongs_to :mock_exam_template
  belongs_to :mock_exam_attempt, optional: true

  has_many :mock_exam_responses, dependent: :destroy

  enum question_type: {
    knowledge: 0,
    maths: 1,
    reasoning: 2,
    data_interp: 3,
    visual_reasoning: 4,
  }

  enum question_format: { text: 0, svg: 1, image: 2 }
  enum difficulty: { easy: 0, medium: 1, hard: 2 }

  validates :section_name, presence: true
  validates :position, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :question_text, presence: true
  validates :correct_option_key, presence: true, inclusion: { in: %w[A B C D] }
  validates :options, presence: true
  validate :options_has_four_entries

  before_save :render_html_fields

  scope :pool, -> { where(mock_exam_attempt_id: nil) }
  scope :for_section, ->(name) { where(section_name: name) }
  scope :for_difficulty, ->(diff) { where(difficulty: diff) }

  def pool_question?
    mock_exam_attempt_id.nil?
  end

  def increment_served!
    increment!(:times_served) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def options_has_four_entries
    return if options.is_a?(Array) && options.length == 4

    errors.add(:options, "must have exactly 4 entries")
  end

  def render_html_fields
    self.question_html = ContentRenderer.new(question_text).finalize[:processed_html] if question_text_changed?
    self.explanation_html = ContentRenderer.new(explanation).finalize[:processed_html] if explanation.present? && explanation_changed?
    if solution_steps.present? && solution_steps_changed?
      self.solution_steps_html = ContentRenderer.new(solution_steps).finalize[:processed_html]
    end
  end
end
