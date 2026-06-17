class AddIndexMockAttemptsTemplateSetStatus < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :mock_exam_attempts,
              %i[mock_exam_template_id pool_set status],
              name: "idx_mock_attempts_template_set_status",
              algorithm: :concurrently
  end
end
