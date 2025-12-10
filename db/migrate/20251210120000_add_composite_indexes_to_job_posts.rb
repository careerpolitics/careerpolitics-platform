class AddCompositeIndexesToJobPosts < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # Composite index for available job posts query (published + approved + post_type + ordering)
    add_index :job_posts,
              [:published, :approved, :post_type, :position, :published_at, :created_at],
              name: 'index_job_posts_on_available_query',
              where: "published = true AND approved = true",
              algorithm: :concurrently,
              if_not_exists: true

    # Index for featured job posts
    add_index :job_posts,
              [:featured, :published, :approved, :position, :published_at, :created_at],
              name: 'index_job_posts_on_featured_query',
              where: "published = true AND approved = true AND featured = true",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

