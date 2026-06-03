module Search
  class JobPost
    DEFAULT_PER_PAGE = 60
    private_constant :DEFAULT_PER_PAGE

    MAX_PER_PAGE = 120
    private_constant :MAX_PER_PAGE

    def self.search_documents(page: 0, per_page: DEFAULT_PER_PAGE, sort_by: nil, sort_direction: nil, term: nil)
      page = page.to_i + 1
      per_page = [(per_page || DEFAULT_PER_PAGE).to_i, MAX_PER_PAGE].min

      relation = ::JobPost.available
      relation = relation.search_job_posts(term) if term.present?
      relation = sort(relation, sort_by, sort_direction)
      results = relation.page(page).per(per_page)

      results.map do |job|
        {
          class_name: "JobPost",
          id: job.id,
          title: job.title,
          path: job.path,
          description: job.description,
          organization_name: job.organization_name,
          category: job.category,
          post_type: job.post_type,
          location: job.location,
          salary_range: job.salary_range,
          published_at: job.published_at,
          readable_publish_date: job.published_at&.strftime("%b %e"),
          published_timestamp: job.published_at&.iso8601,
        }
      end
    end

    def self.sort(relation, sort_by, sort_direction)
      return relation.reorder(sort_by => sort_direction) if sort_by&.to_sym == :published_at && sort_direction

      relation.recent
    end
    private_class_method :sort
  end
end
