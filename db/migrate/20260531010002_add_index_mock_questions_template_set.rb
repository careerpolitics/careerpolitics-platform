class AddIndexMockQuestionsTemplateSet < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :mock_exam_questions,
              %i[mock_exam_template_id pool_set],
              name: "idx_mock_questions_template_set",
              where: "mock_exam_attempt_id IS NULL AND pool_set IS NOT NULL",
              algorithm: :concurrently
  end
end
