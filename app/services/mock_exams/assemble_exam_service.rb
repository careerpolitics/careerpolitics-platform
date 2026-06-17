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
      MockExamQuestion.where(id: questions.map(&:id)).update_all("times_served = times_served + 1") # rubocop:disable Rails/SkipsModelValidations
      questions
    end

    def select_random
      published = @template.published_sets.keys
      return nil if published.empty?

      # Prefer sets the user hasn't attempted; fall back to any published set
      attempted_sets = @user.mock_exam_attempts
                            .for_template(@template)
                            .where.not(pool_set: nil)
                            .pluck(:pool_set).uniq
      unattempted = published - attempted_sets
      chosen_set = unattempted.any? ? unattempted.sample : published.sample

      @pool_set = chosen_set
      select_from_set
    end

    def copy_questions_for_attempt(source_questions)
      ordered = order_by_section(source_questions)
      ordered.map.with_index(1) do |src, idx|
        attrs = src.attributes.slice(*COPY_ATTRS)
        MockExamQuestion.new(attrs.merge(
          source_question_id: src.id,
          pool_set: src.pool_set,
          position: idx,
          mock_exam_attempt_id: nil,
          ))
      end
    end

    def order_by_section(questions)
      section_order = @template.sections_config.map { |s| s["name"] }
      questions.sort_by do |q|
        [section_order.index(q.section_name) || 999, q.position || 0]
      end
    end

    def section_counts
      @section_counts ||= @template.sections_config.each_with_object({}) do |section, hash|
        hash[section["name"]] = section["count"]
      end
    end
  end
end
