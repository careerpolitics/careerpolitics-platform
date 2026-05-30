class CreateMockExamTemplateStats < ActiveRecord::Migration[7.0]
  def change
    create_table :mock_exam_template_stats do |t|
      t.references :mock_exam_template, null: false, foreign_key: true, index: { unique: true }
      t.integer :total_attempts, default: 0
      t.integer :unique_users, default: 0
      t.decimal :average_score, precision: 8, scale: 2, default: 0
      t.decimal :median_score, precision: 8, scale: 2, default: 0
      t.decimal :highest_score, precision: 8, scale: 2, default: 0
      t.decimal :lowest_score, precision: 8, scale: 2, default: 0
      t.decimal :average_accuracy, precision: 5, scale: 1, default: 0
      t.decimal :average_time_seconds, precision: 10, scale: 0, default: 0
      t.jsonb :score_distribution, default: []
      t.jsonb :section_averages, default: {}
      t.jsonb :difficulty_accuracy, default: {}
      t.decimal :completion_rate, precision: 5, scale: 1, default: 0
      t.datetime :last_refreshed_at
      t.timestamps
    end
  end
end
