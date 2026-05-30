class MockExamResponse < ApplicationRecord
  belongs_to :mock_exam_attempt
  belongs_to :mock_exam_question

  validates :mock_exam_question_id, uniqueness: { scope: :mock_exam_attempt_id }
  validates :selected_option_key, inclusion: { in: %w[A B C D], allow_nil: true }

  def answered?
    selected_option_key.present?
  end

  def correct?
    is_correct
  end

  def evaluate!
    return unless answered?

    self.is_correct = selected_option_key == mock_exam_question.correct_option_key
    save!
  end
end
