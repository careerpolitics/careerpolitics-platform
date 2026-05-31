class AddPoolSetToMockExamQuestions < ActiveRecord::Migration[7.0]
  def up
    add_column :mock_exam_questions, :pool_set, :integer unless column_exists?(:mock_exam_questions, :pool_set)
    unless column_exists?(:mock_exam_questions, :set_published)
      add_column :mock_exam_questions, :set_published, :boolean, default: false, null: false
    end
    add_column :mock_exam_questions, :source_question_id, :integer unless column_exists?(:mock_exam_questions, :source_question_id)
  end

  def down
    remove_column :mock_exam_questions, :source_question_id if column_exists?(:mock_exam_questions, :source_question_id)
    remove_column :mock_exam_questions, :set_published if column_exists?(:mock_exam_questions, :set_published)
    remove_column :mock_exam_questions, :pool_set if column_exists?(:mock_exam_questions, :pool_set)
  end
end
