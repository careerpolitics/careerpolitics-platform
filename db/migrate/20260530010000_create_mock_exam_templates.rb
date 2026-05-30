class CreateMockExamTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :mock_exam_templates do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :exam_category, default: 0, null: false
      t.integer :total_questions, null: false
      t.integer :duration_minutes, null: false
      t.decimal :marks_per_correct, precision: 4, scale: 2, default: 2.0
      t.decimal :negative_marks_per_wrong, precision: 4, scale: 2, default: 0.67
      t.integer :question_display_mode, default: 0, null: false
      t.text :ai_prompt_context
      t.jsonb :sections_config, null: false, default: []
      t.boolean :has_calculator, default: false
      t.boolean :has_scratchpad, default: true
      t.integer :difficulty_level, default: 3, null: false
      t.boolean :active, default: true
      t.boolean :published, default: false
      t.references :subforem, null: true, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :mock_exam_templates, :slug, unique: true
    add_index :mock_exam_templates, %i[active published]
  end
end
