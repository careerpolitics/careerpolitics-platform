class AddStructuredFieldsToJobPosts < ActiveRecord::Migration[7.0]
  def change
    add_column :job_posts, :organization_name, :string
    add_column :job_posts, :location, :string
    add_column :job_posts, :deadline_at, :datetime
    add_column :job_posts, :employment_type, :string
    add_column :job_posts, :salary_range, :string
    add_column :job_posts, :qualification, :text
    add_column :job_posts, :vacancies, :integer
    add_column :job_posts, :source_name, :string
    add_column :job_posts, :source_url, :string
    add_column :job_posts, :important_dates, :text

  end
end
