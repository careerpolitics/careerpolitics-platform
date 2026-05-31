class AddPoolSetToMockExamQuestions < ActiveRecord::Migration[7.0]
  def change
    add_column :mock_exam_questions, :pool_set, :integer
    add_column :mock_exam_questions, :set_published, :boolean, default: false, null: false
    add_column :mock_exam_questions, :source_question_id, :integer

    add_index :mock_exam_questions,
              %i[mock_exam_template_id pool_set],
              name: "idx_mock_questions_template_set",
              where: "mock_exam_attempt_id IS NULL AND pool_set IS NOT NULL"
  end
end
