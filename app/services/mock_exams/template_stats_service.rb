module MockExams
  class TemplateStatsService
    def initialize(template)
      @template = template
      @attempts = template.mock_exam_attempts.submitted_or_timed_out
    end

    def call
      stats = @template.mock_exam_template_stat || @template.build_mock_exam_template_stat

      stats.update!(
        total_attempts: @attempts.count,
        unique_users: @attempts.select(:user_id).distinct.count,
        average_score: @attempts.average(:total_score)&.round(2) || 0,
        median_score: calculate_median,
        highest_score: @attempts.maximum(:total_score) || 0,
        lowest_score: @attempts.minimum(:total_score) || 0,
        average_accuracy: @attempts.average(:accuracy_percent)&.round(1) || 0,
        average_time_seconds: calculate_avg_time,
        score_distribution: build_score_histogram,
        section_averages: build_section_averages,
        difficulty_accuracy: build_difficulty_accuracy,
        completion_rate: calculate_completion_rate,
        last_refreshed_at: Time.current,
        )

      stats
    end

    private

    def calculate_median
      scores = @attempts.order(:total_score).pluck(:total_score)
      return 0 if scores.empty?

      mid = scores.length / 2
      scores.length.odd? ? scores[mid] : ((scores[mid - 1] + scores[mid]) / 2.0).round(2)
    end

    def build_score_histogram
      max = @template.max_possible_score
      return [] if max.zero?

      bucket_size = (max / 10.0).ceil
      counts = @attempts
                 .group(Arel.sql("width_bucket(total_score, 0, #{max.to_f + bucket_size}, 10)"))
                 .count

      (0..9).map do |i|
        min_val = i * bucket_size
        max_val = (i + 1) * bucket_size
        { min: min_val, max: max_val, count: counts[i + 1] || 0 }
      end
    end

    def build_section_averages
      return {} if @attempts.none?

      section_data = {}
      @attempts.pluck(:section_scores).compact.each do |scores|
        scores.each do |section_name, data|
          section_data[section_name] ||= { scores: [], corrects: [], wrongs: [] }
          section_data[section_name][:scores] << (data["score"] || 0).to_f
          section_data[section_name][:corrects] << (data["correct"] || 0).to_i
          section_data[section_name][:wrongs] << (data["incorrect"] || data["wrong"] || 0).to_i
        end
      end

      section_data.transform_values do |data|
        count = data[:scores].size
        {
          avg_score: (data[:scores].sum / count.to_f).round(2),
          avg_correct: (data[:corrects].sum / count.to_f).round(1),
          avg_wrong: (data[:wrongs].sum / count.to_f).round(1),
        }
      end
    end

    def build_difficulty_accuracy
      responses = MockExamResponse
                    .joins(:mock_exam_question)
                    .where(mock_exam_attempt: @attempts)
                    .where.not(selected_option_key: nil)

      result = {}
      %w[easy medium hard].each do |diff|
        diff_responses = responses.where(mock_exam_questions: { difficulty: diff })
        total = diff_responses.count
        correct = diff_responses.where(is_correct: true).count
        result[diff] = total.positive? ? (correct.to_f / total * 100).round(1) : 0
      end

      result
    end

    def calculate_completion_rate
      total_started = @template.mock_exam_attempts.count
      return 0 if total_started.zero?

      (@attempts.count.to_f / total_started * 100).round(1)
    end

    def calculate_avg_time
      @attempts.where.not(submitted_at: nil)
               .average(Arel.sql("EXTRACT(EPOCH FROM submitted_at - started_at)"))
        &.round(0) || 0
    end
  end
end
