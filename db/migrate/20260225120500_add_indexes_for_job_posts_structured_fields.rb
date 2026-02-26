class AddIndexesForJobPostsStructuredFields < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :job_posts, :deadline_at, algorithm: :concurrently
    add_index :job_posts, :employment_type, algorithm: :concurrently
  end
end
