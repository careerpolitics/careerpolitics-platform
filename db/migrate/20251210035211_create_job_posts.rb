class CreateJobPosts < ActiveRecord::Migration[7.0]
  def change
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
      t.string :slug # For friendly URLs
      t.boolean :approved, default: false, null: false
      t.integer :position, default: 0, null: false
      t.boolean :featured, default: false, null: false

      t.timestamps
    end

    # Single column indexes
    add_index :job_posts, :published
    add_index :job_posts, :post_type
    add_index :job_posts, :category
    add_index :job_posts, :slug, unique: true
    add_index :job_posts, :published_at
    add_index :job_posts, :approved
    add_index :job_posts, :position
    add_index :job_posts, :featured

    # Composite indexes for optimized queries
    add_index :job_posts,
              [:published, :approved, :post_type, :position, :published_at, :created_at],
              name: 'index_job_posts_on_available_query',
              where: "published = true AND approved = true"

    add_index :job_posts,
              [:featured, :published, :approved, :position, :published_at, :created_at],
              name: 'index_job_posts_on_featured_query',
              where: "published = true AND approved = true AND featured = true"
  end
end
