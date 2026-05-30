class CreateMockExamQuestions < ActiveRecord::Migration[7.0]
  def change
    create_table :mock_exam_questions do |t|
      t.references :mock_exam_template, null: false, foreign_key: true
      t.references :mock_exam_attempt, null: true, foreign_key: true
      t.string :section_name, null: false
      t.integer :position, null: false
      t.integer :question_type, default: 0, null: false
      t.text :question_text, null: false
      t.text :question_html
      t.integer :question_format, default: 0, null: false
      t.text :question_svg
      t.jsonb :options, null: false, default: []
      t.text :solution_steps
      t.text :solution_steps_html
      t.string :correct_option_key, null: false
      t.text :explanation
      t.text :explanation_html
      t.integer :difficulty, default: 1, null: false
      t.string :topic_tags, array: true, default: []
      t.text :text_hi
      t.text :explanation_hi
      t.integer :times_served, default: 0, null: false
      t.jsonb :ai_generation_metadata, default: {}
      t.timestamps
    end

    add_index :mock_exam_questions,
              %i[mock_exam_attempt_id position],
              name: "idx_mock_questions_attempt_position"
    add_index :mock_exam_questions,
              %i[mock_exam_template_id mock_exam_attempt_id],
              name: "idx_mock_questions_pool",
              where: "mock_exam_attempt_id IS NULL"
  end
end
