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
                             .includes(:mock_exam_template_stat, :tag)
                             .order(created_at: :desc)

    respond_to do |format|
      format.html
      format.json do
        followed = if current_user
                     current_user.follows.where(followable_type: "Tag")
                                 .includes(:followable)
                                 .filter_map { |f| f.followable ? { id: f.followable.id, name: f.followable.name } : nil }
                   else
                     []
                   end
        render json: {
          templates: @mock_exam_templates.map { |t| template_json(t) },
          followed_tags: followed,
        }
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
    published = @template.published_sets
    set_numbers = published.keys

    # Batch: attempt counts per set (1 query)
    attempts_by_set = @template.mock_exam_attempts
                               .where(pool_set: set_numbers)
                               .group(:pool_set).count

    # Batch: user's latest attempt per set (1 query)
    user_attempts_by_set = {}
    if current_user
      current_user.mock_exam_attempts
                  .for_template(@template)
                  .where(pool_set: set_numbers)
                  .submitted_or_timed_out
                  .order(submitted_at: :desc)
                  .each { |a| user_attempts_by_set[a.pool_set] ||= a }
    end

    # Batch: difficulties per set (1 query)
    diff_rows = @template.pool_questions
                         .where(pool_set: set_numbers, set_published: true)
                         .group(:pool_set, :difficulty).count
    difficulties_by_set = diff_rows.each_with_object({}) do |((ps, diff), cnt), h|
      (h[ps] ||= {})[diff] = cnt
    end

    # Batch: set labels (1 query for min created_at)
    min_dates = @template.pool_questions
                         .where(pool_set: set_numbers)
                         .group(:pool_set).minimum(:created_at)

    sets_data = published.map do |set_number, count|
      user_attempt = user_attempts_by_set[set_number]
      diffs = difficulties_by_set[set_number] || {}
      primary_difficulty = diffs.max_by { |_, v| v }&.first || "mixed"
      set_date = min_dates[set_number]
      label = set_date ? "#{set_date.strftime("%d-%m")}-#{Digest::MD5.hexdigest("#{@template.id}-#{set_number}")[0, 3]}" : "Set #{set_number}"
      {
        set_number: set_number,
        question_count: count,
        attempts_count: attempts_by_set[set_number] || 0,
        user_attempted: user_attempt.present?,
        difficulty: primary_difficulty,
        difficulty_breakdown: diffs,
        label: label,
        user_attempt_data: user_attempt ? {
          attempt_id: user_attempt.id,
          total_score: user_attempt.total_score,
          max_possible_score: user_attempt.max_possible_score,
          accuracy_percent: user_attempt.accuracy_percent,
          percentile: user_attempt.percentile,
        } : nil,
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
      published_sets_count: template.published_set_count,
      tag_list: template.tag ? [{ name: template.tag.name, id: template.tag.id }] : [],
    }
  end

  def set_template_by_slug
    @template = MockExamTemplate.includes(:tag).find_by!(slug: params[:slug], active: true, published: true)
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
