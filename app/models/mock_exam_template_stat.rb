class MockExamTemplateStat < ApplicationRecord
  belongs_to :mock_exam_template

  validates :mock_exam_template_id, uniqueness: true

  def sufficient_data?
    total_attempts >= 5
  end
end
