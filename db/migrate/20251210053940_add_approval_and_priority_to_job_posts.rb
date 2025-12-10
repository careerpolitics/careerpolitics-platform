class AddApprovalAndPriorityToJobPosts < ActiveRecord::Migration[7.0]
  def change
    add_column :job_posts, :approved, :boolean, default: false, null: false
    add_column :job_posts, :position, :integer, default: 0, null: false
    add_index :job_posts, :approved
    add_index :job_posts, :position
  end
end
