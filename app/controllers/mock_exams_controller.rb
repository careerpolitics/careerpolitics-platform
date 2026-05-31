class MockExamsController < ApplicationController
  before_action :set_cache_control_headers, only: %i[index show]
  before_action :authenticate_user!, only: %i[dashboard]
  before_action :set_template_by_slug, only: %i[show leaderboard stats sets]

  rescue_from ActiveRecord::RecordNotFound do
    render file: Rails.root.join("public/404.html"), layout: false, status: :not_found
  end

  def index
    @mock_exam_templates = MockExamTemplate
                             .active_published
                             .for_subforem(RequestStore.store[:subforem])
                             .includes(:mock_exam_template_stat)
                             .order(created_at: :desc)

    respond_to do |format|
      format.html
      format.json do
        render json: @mock_exam_templates.map { |t| template_json(t) }
      end
    end
  end

  def show
    @stats = @template.mock_exam_template_stat

    respond_to do |format|
      format.html
      format.json do
        render json: template_json(@template).merge(
          stats: @stats ? stats_json(@stats) : nil,
          pool_ready: @template.pool_ready?,
          can_attempt: can_attempt?,
          )
      end
    end
  end

  def leaderboard
    entries = build_leaderboard_entries
    render json: { entries: entries }
  end

  def sets
    sets_data = @template.published_sets.map do |set_number, count|
      attempts_for_set = @template.mock_exam_attempts.where(pool_set: set_number).count
      user_attempted = current_user ? current_user.mock_exam_attempts
                                                  .for_template(@template)
                                                  .where(pool_set: set_number).exists? : false
      {
        set_number: set_number,
        question_count: count,
        attempts_count: attempts_for_set,
        user_attempted: user_attempted,
      }
    end
    render json: { sets: sets_data }
  end

  def stats
    stat = @template.mock_exam_template_stat
    render json: stat ? full_stats_json(stat) : { error: "No stats available" }
  end

  def dashboard
    attempts = current_user.mock_exam_attempts
                           .submitted_or_timed_out
                           .includes(:mock_exam_template)
                           .order(submitted_at: :desc)
                           .limit(50)

    completed = attempts.count
    scores = attempts.pluck(:accuracy_percent).compact

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total_attempts: current_user.mock_exam_attempts.count,
          completed_attempts: completed,
          best_score: scores.max,
          avg_accuracy: scores.any? ? (scores.sum / scores.size).round(1) : nil,
          streak_days: calculate_streak,
          trend: attempts.first(20).reverse.map { |a| { accuracy_percent: a.accuracy_percent, date: a.submitted_at&.to_date } },
          section_accuracy: build_section_accuracy(attempts),
          attempts: attempts.map { |a| dashboard_attempt_json(a) },
        }
      end
    end
  end

  private

  def template_json(template)
    {
      id: template.id,
      title: template.title,
      slug: template.slug,
      description: template.description,
      exam_category: template.exam_category,
      total_questions: template.total_questions,
      duration_minutes: template.duration_minutes,
      marks_per_correct: template.marks_per_correct,
      negative_marks_per_wrong: template.negative_marks_per_wrong,
      difficulty_level: template.difficulty_level,
      sections_config: template.sections_config,
      has_calculator: template.has_calculator,
      has_scratchpad: template.has_scratchpad,
      sets_count: template.available_sets.size,
    }
  end

  def set_template_by_slug
    @template = MockExamTemplate.find_by!(slug: params[:slug], active: true, published: true)
  end

  def stats_json(stats)
    return nil unless stats&.sufficient_data?

    {
      total_attempts: stats.total_attempts,
      unique_users: stats.unique_users,
      average_score: stats.average_score,
      median_score: stats.median_score,
      highest_score: stats.highest_score,
      average_accuracy: stats.average_accuracy,
      average_time_seconds: stats.average_time_seconds,
      score_distribution: stats.score_distribution,
      completion_rate: stats.completion_rate,
    }
  end

  def full_stats_json(stats)
    base = stats_json(stats) || {}
    base.merge(
      section_averages: stats.section_averages,
      difficulty_accuracy: stats.difficulty_accuracy,
      last_refreshed_at: stats.last_refreshed_at,
      )
  end

  def build_leaderboard_entries
    scope = @template.mock_exam_attempts.submitted_or_timed_out

    case params[:filter]
    when "week"
      scope = scope.where("submitted_at >= ?", 1.week.ago)
    when "month"
      scope = scope.where("submitted_at >= ?", 1.month.ago)
    end

    scope = scope.where(pool_set: params[:set]) if params[:set].present?

    scope
      .order(total_score: :desc, submitted_at: :asc)
      .limit(20)
      .includes(:user)
      .map do |attempt|
      {
        attempt_id: attempt.id,
        user_id: attempt.user_id,
        username: attempt.user.username,
        name: attempt.user.name.presence || attempt.user.username,
        profile_image: attempt.user.profile_image_90,
        total_score: attempt.total_score,
        max_possible_score: attempt.max_possible_score,
        accuracy_percent: attempt.accuracy_percent,
        pool_set: attempt.pool_set,
        time_taken_seconds: attempt.submitted_at && attempt.started_at ?
                              (attempt.submitted_at - attempt.started_at).to_i : nil,
      }
    end
  end

  def dashboard_attempt_json(attempt)
    {
      id: attempt.id,
      template_title: attempt.mock_exam_template.title,
      template_slug: attempt.mock_exam_template.slug,
      total_score: attempt.total_score,
      max_possible_score: attempt.max_possible_score,
      accuracy_percent: attempt.accuracy_percent,
      percentile: attempt.percentile,
      submitted_at: attempt.submitted_at,
    }
  end

  def build_section_accuracy(attempts)
    section_data = {}
    attempts.pluck(:section_scores).compact.each do |scores|
      scores.each do |name, data|
        section_data[name] ||= { correct: 0, total: 0 }
        section_data[name][:correct] += (data["correct"] || 0)
        section_data[name][:total] += (data["correct"] || 0) + (data["wrong"] || 0) + (data["unanswered"] || 0)
      end
    end

    section_data.transform_values do |d|
      d[:total].positive? ? (d[:correct].to_f / d[:total] * 100).round(1) : 0
    end
  end

  def calculate_streak
    dates = current_user.mock_exam_attempts
                        .where.not(submitted_at: nil)
                        .order(submitted_at: :desc)
                        .pluck(Arel.sql("DATE(submitted_at)"))
                        .uniq

    streak = 0
    check_date = Date.current
    dates.each do |d|
      break unless d == check_date || d == check_date - 1.day

      streak += 1 if d == check_date
      check_date = d - 1.day
    end
    streak
  end

  def can_attempt?
    current_user.present?
  end
end
