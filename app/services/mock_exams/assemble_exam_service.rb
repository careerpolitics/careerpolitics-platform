module MockExams
  class AssembleExamService
    POOL_EXHAUSTION_THRESHOLD = 0.6

    def initialize(template, user)
      @template = template
      @user = user
    end

    def call
      seen_ids = previously_seen_question_ids
      pool = @template.pool_questions
      available = pool.where.not(id: seen_ids)

      if can_serve_from_pool?(available)
        assemble_from_pool(available)
      else
        nil
      end
    end

    private

    def previously_seen_question_ids
      MockExamResponse
        .joins(:mock_exam_question)
        .where(mock_exam_attempt: @user.mock_exam_attempts.for_template(@template))
        .pluck(:mock_exam_question_id)
        .uniq
    end

    def can_serve_from_pool?(available)
      return false unless @template.pool_ready?

      needed_per_section = section_counts
      needed_per_section.all? do |section_name, count|
        available.for_section(section_name).count >= count
      end
    end

    def assemble_from_pool(available)
      selected = []

      section_counts.each do |section_name, count|
        section_qs = available
                       .for_section(section_name)
                       .order(Arel.sql("RANDOM()"))
                       .limit(count)
                       .to_a
        selected.concat(section_qs)
      end

      selected.shuffle!
      selected.each_with_index do |question, idx|
        question.increment_served!
      end

      selected
    end

    def section_counts
      @section_counts ||= @template.sections_config.each_with_object({}) do |section, hash|
        hash[section["name"]] = section["count"]
      end
    end
  end
end
