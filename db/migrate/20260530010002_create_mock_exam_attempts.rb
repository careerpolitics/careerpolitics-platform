class CreateMockExamAttempts < ActiveRecord::Migration[7.0]
  def change
    create_table :mock_exam_attempts do |t|
      t.references :mock_exam_template, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.datetime :started_at, null: false
      t.datetime :submitted_at
      t.datetime :expires_at, null: false
      t.decimal :total_score, precision: 8, scale: 2
      t.decimal :max_possible_score, precision: 8, scale: 2
      t.integer :correct_count, default: 0
      t.integer :incorrect_count, default: 0
      t.integer :unanswered_count, default: 0
      t.jsonb :section_scores, default: {}
      t.jsonb :time_per_question, default: {}
      t.decimal :percentile, precision: 5, scale: 2
      t.integer :rank
      t.decimal :accuracy_percent, precision: 5, scale: 1
      t.decimal :avg_time_per_question, precision: 8, scale: 1
      t.integer :questions_source, default: 0, null: false
      t.timestamps
    end

    add_index :mock_exam_attempts, %i[user_id mock_exam_template_id], name: "idx_mock_attempts_user_template"
    add_index :mock_exam_attempts, :status
  end
end
