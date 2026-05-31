module MockExams
  class ScoringService
    def initialize(attempt)
      @attempt = attempt
      @template = attempt.mock_exam_template
    end

    def call
      evaluate_responses
      compute_scores
      compute_section_scores
      compute_ranking
      @attempt.save!

      MockExams::RefreshTemplateStatsWorker.perform_async(@template.id)
      @attempt
    end

    private

    def evaluate_responses
      @attempt.mock_exam_responses.includes(:mock_exam_question).find_each(&:evaluate!)
    end

    def compute_scores
      responses = @attempt.mock_exam_responses.reload

      correct = responses.where(is_correct: true).count
      incorrect = responses.where(is_correct: false).where.not(selected_option_key: nil).count
      unanswered = @template.total_questions - correct - incorrect

      score = (correct * @template.marks_per_correct) - (incorrect * @template.negative_marks_per_wrong)

      @attempt.correct_count = correct
      @attempt.incorrect_count = incorrect
      @attempt.unanswered_count = unanswered
      @attempt.total_score = [score, 0].max
      @attempt.max_possible_score = @template.max_possible_score
      @attempt.accuracy_percent = (if @template.total_questions.positive?
                                     (correct.to_f / @template.total_questions * 100).round(1)
                                   else
                                     0
                                   end)

      time_values = @attempt.time_per_question.values.map(&:to_f)
      @attempt.avg_time_per_question = time_values.any? ? (time_values.sum / time_values.size).round(1) : 0
    end

    def compute_section_scores
      section_scores = {}

      responses_by_section = @attempt.mock_exam_responses.includes(:mock_exam_question).group_by do |r|
        r.mock_exam_question.section_name
      end

      responses_by_section.each do |section_name, responses|
        correct = responses.count(&:correct?)
        wrong = responses.count { |r| r.answered? && !r.correct? }
        score = (correct * @template.marks_per_correct) - (wrong * @template.negative_marks_per_wrong)

        section_scores[section_name] = {
          correct: correct,
          wrong: wrong,
          unanswered: responses.count { |r| !r.answered? },
          score: [score, 0].max.round(2)
        }
      end

      @attempt.section_scores = section_scores
    end

    def compute_ranking
      submitted = @template.mock_exam_attempts.submitted_or_timed_out
      total = submitted.count

      if total > 1
        below = submitted.where("total_score < ?", @attempt.total_score).count
        @attempt.percentile = ((below.to_f / (total - 1)) * 100).round(1)
      else
        @attempt.percentile = 100.0
      end

      @attempt.rank = rank_for(submitted)
    end

    # Rank = 1 + number of attempts that beat this one.
    # An attempt is beaten by another when the other has a higher score, or an
    # equal score completed in less time (tiebreak: faster completion ranks
    # higher). Completion time is derived from submitted_at - started_at; this
    # attempt's own time is treated as last when its submitted_at is missing.
    def rank_for(submitted)
      this_time = attempt_completion_seconds(@attempt)

      ahead = submitted.where("total_score > ?", @attempt.total_score)

      if this_time
        ahead = ahead.or(
          submitted.where(total_score: @attempt.total_score)
            .where.not(id: @attempt.id)
            .where(
              "EXTRACT(EPOCH FROM (submitted_at - started_at)) < ?",
              this_time,
            ),
        )
      end

      ahead.count + 1
    end

    def attempt_completion_seconds(attempt)
      return unless attempt.submitted_at && attempt.started_at

      (attempt.submitted_at - attempt.started_at).to_i
    end
  end
end
