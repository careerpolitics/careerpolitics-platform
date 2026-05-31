module MockExams
  class AssembleExamService
    COPY_ATTRS = %w[
      mock_exam_template_id section_name question_type question_text question_html
      question_format question_svg options correct_option_key explanation explanation_html
      solution_steps solution_steps_html difficulty topic_tags text_hi explanation_hi
      ai_generation_metadata
    ].freeze

    def initialize(template, user, pool_set: nil)
      @template = template
      @user = user
      @pool_set = pool_set
    end

    def call
      source_questions = if @pool_set
                           select_from_set
                         else
                           select_random
                         end

      return nil unless source_questions

      copy_questions_for_attempt(source_questions)
    end

    attr_reader :pool_set

    private

    def select_from_set
      questions = @template.set_questions(@pool_set).where(set_published: true).to_a
      return nil if questions.empty?
      questions.each(&:increment_served!)
      questions
    end

    def select_random
      seen_source_ids = previously_seen_source_ids
      pool = @template.pool_questions.where(set_published: true)
      available = pool.where.not(id: seen_source_ids)

      if can_serve_from_pool?(available)
        pick_from_pool(available)
      else
        nil
      end
    end

    def previously_seen_source_ids
      @user.mock_exam_attempts
           .for_template(@template)
           .joins(:mock_exam_questions)
           .where.not(mock_exam_questions: { source_question_id: nil })
           .pluck("mock_exam_questions.source_question_id")
           .uniq
    end

    def can_serve_from_pool?(available)
      return false unless @template.pool_ready?
      section_counts.all? do |section_name, count|
        available.for_section(section_name).count >= count
      end
    end

    def pick_from_pool(available)
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
      selected.each(&:increment_served!)
      selected
    end

    def copy_questions_for_attempt(source_questions)
      source_questions.map.with_index(1) do |src, idx|
        attrs = src.attributes.slice(*COPY_ATTRS)
        MockExamQuestion.new(attrs.merge(
          source_question_id: src.id,
          pool_set: src.pool_set,
          position: idx,
          mock_exam_attempt_id: nil,
          ))
      end
    end

    def section_counts
      @section_counts ||= @template.sections_config.each_with_object({}) do |section, hash|
        hash[section["name"]] = section["count"]
      end
    end
  end
end
