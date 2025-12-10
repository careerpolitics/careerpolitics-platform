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

      t.timestamps
    end

    add_index :job_posts, :published
    add_index :job_posts, :post_type
    add_index :job_posts, :category
    add_index :job_posts, :slug, unique: true
    add_index :job_posts, :published_at
  end
end
