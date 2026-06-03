module Search
  class MockExam
    DEFAULT_PER_PAGE = 60
    private_constant :DEFAULT_PER_PAGE

    MAX_PER_PAGE = 120
    private_constant :MAX_PER_PAGE

    def self.search_documents(page: 0, per_page: DEFAULT_PER_PAGE, sort_by: nil, sort_direction: nil, term: nil)
      page = page.to_i + 1
      per_page = [(per_page || DEFAULT_PER_PAGE).to_i, MAX_PER_PAGE].min

      relation = MockExamTemplate.active_published
      relation = relation.search_mock_exams(term) if term.present?
      relation = sort(relation, sort_by, sort_direction)
      results = relation.page(page).per(per_page)

      results.map do |template|
        {
          class_name: "MockExamTemplate",
          id: template.id,
          title: template.title,
          path: "/mock_exams/#{template.slug}",
          description: template.description,
          total_questions: template.total_questions,
          duration_minutes: template.duration_minutes,
          difficulty_level: template.difficulty_level,
          exam_category: template.exam_category,
          tag_name: template.tag&.name,
          published_at: template.created_at,
          readable_publish_date: template.created_at&.strftime("%b %e"),
          published_timestamp: template.created_at&.iso8601,
        }
      end
    end

    def self.sort(relation, sort_by, sort_direction)
      return relation.reorder(sort_by => sort_direction) if sort_by&.to_sym == :created_at && sort_direction

      relation.reorder(created_at: :desc)
    end
    private_class_method :sort
  end
end
