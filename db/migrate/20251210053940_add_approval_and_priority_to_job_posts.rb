class AddApprovalAndPriorityToJobPosts < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # Safe column additions
    add_column :job_posts, :approved, :boolean, default: false, null: false
    add_column :job_posts, :position, :integer, default: 0, null: false

    # Safe concurrent indexes (required by strong_migrations)
    add_index :job_posts, :approved, algorithm: :concurrently
    add_index :job_posts, :position, algorithm: :concurrently
  end
end
