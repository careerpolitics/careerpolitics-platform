class CreateJobPosts < ActiveRecord::Migration[7.0]
  # Required for concurrent index creation
  disable_ddl_transaction!

  def change
    # Table creation is safe inside transaction
    create_table :job_posts do |t|
      t.string :title, null: false
      t.text :description
      t.string :category
      t.string :post_type # 'new_update', 'admit_card', 'online_form'
      t.string :link
      t.string :color # For card background color
      t.boolean :published, default: false
      t.datetime :published_at
      t.references :user, null: false, foreign_key: true
      t.string :slug
      t.boolean :approved, default: false, null: false
      t.integer :position, default: 0, null: false
      t.boolean :featured, default: false, null: false

      t.timestamps
    end

    # Safe single-column indexes (concurrently)
    add_index :job_posts, :published, algorithm: :concurrently
    add_index :job_posts, :post_type, algorithm: :concurrently
    add_index :job_posts, :category, algorithm: :concurrently
    add_index :job_posts, :slug, unique: true, algorithm: :concurrently
    add_index :job_posts, :published_at, algorithm: :concurrently
    add_index :job_posts, :approved, algorithm: :concurrently
    add_index :job_posts, :position, algorithm: :concurrently
    add_index :job_posts, :featured, algorithm: :concurrently

    # Composite indexes (concurrently + smaller column sets)
    add_index :job_posts,
              [:published, :approved, :post_type, :position],
              name: 'index_job_posts_on_available_query',
              where: "published = true AND approved = true",
              algorithm: :concurrently

    add_index :job_posts,
              [:featured, :published, :approved, :position],
              name: 'index_job_posts_on_featured_query',
              where: "published = true AND approved = true AND featured = true",
              algorithm: :concurrently
  end
end
