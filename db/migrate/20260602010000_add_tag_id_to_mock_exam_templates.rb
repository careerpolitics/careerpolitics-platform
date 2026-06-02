class AddTagIdToMockExamTemplates < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    unless column_exists?(:mock_exam_templates, :tag_id)
      add_column :mock_exam_templates, :tag_id, :bigint
    end

    unless index_exists?(:mock_exam_templates, :tag_id)
      add_index :mock_exam_templates, :tag_id, algorithm: :concurrently
    end
  end
end
