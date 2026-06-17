class AddIndexMockQuestionsPublishedSets < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :mock_exam_questions,
              %i[mock_exam_template_id pool_set],
              name: "idx_mock_questions_published_sets",
              where: "(mock_exam_attempt_id IS NULL) AND (pool_set IS NOT NULL) AND (set_published = true)",
              algorithm: :concurrently
  end
end
