class AddFeaturedToJobPosts < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column :job_posts, :featured, :boolean, default: false, null: false
    add_index :job_posts, :featured, algorithm: :concurrently
  end
end
