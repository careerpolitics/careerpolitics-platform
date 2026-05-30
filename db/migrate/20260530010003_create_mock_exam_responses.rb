class CreateMockExamResponses < ActiveRecord::Migration[7.0]
  def change
    create_table :mock_exam_responses do |t|
      t.references :mock_exam_attempt, null: false, foreign_key: true
      t.references :mock_exam_question, null: false, foreign_key: true
      t.string :selected_option_key
      t.boolean :marked_for_review, default: false, null: false
      t.integer :time_spent_seconds, default: 0
      t.boolean :is_correct
      t.timestamps
    end

    add_index :mock_exam_responses, %i[mock_exam_attempt_id mock_exam_question_id],
              unique: true, name: "idx_mock_responses_attempt_question"
  end
end
