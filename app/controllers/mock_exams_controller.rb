class MockExamsController < ApplicationController
  before_action :set_cache_control_headers, only: %i[index show], unless: -> { request.format.json? }
  before_action :authenticate_user!, only: %i[dashboard show sets leaderboard stats]
  before_action :set_template_by_slug, only: %i[show leaderboard stats sets]

  rescue_from ActiveRecord::RecordNotFound do
    render file: Rails.public_path.join("404.html"), layout: false, status: :not_found
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
        template_ids = @mock_exam_templates.map(&:id)
        @published_counts = MockExamQuestion
                              .where(mock_exam_template_id: template_ids, mock_exam_attempt_id: nil, set_published: true)
                              .where.not(pool_set: nil)
                              .group(:mock_exam_template_id)
                              .distinct.count(:pool_set)
        render json: {
          templates: @mock_exam_templates.map { |t| template_json(t) },
          followed_tags: followed,
          user_signed_in: current_user.present?,
          is_premium: current_user&.cached_base_subscriber? || false,
          trial_attempts_remaining: premium_attempts_remaining,
          upgrade_url: premium_upgrade_url,
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
          user_signed_in: current_user.present?,
          is_premium: current_user&.cached_base_subscriber? || false,
          trial_attempts_remaining: premium_attempts_remaining,
          upgrade_url: premium_upgrade_url,
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

    attempts_by_set = @template.mock_exam_attempts
                               .where(pool_set: set_numbers)
                               .group(:pool_set).count

    user_bests = if current_user
                   current_user.mock_exam_attempts
                               .for_template(@template)
                               .submitted_or_timed_out
                               .where(pool_set: set_numbers)
                               .order(total_score: :desc, submitted_at: :desc)
                               .index_by(&:pool_set)
                 else
                   {}
                 end

    difficulties_by_set = @template.pool_questions
                                   .where(pool_set: set_numbers, set_published: true)
                                   .group(:pool_set, :difficulty).count

    labels_by_set = @template.pool_questions
                             .where(pool_set: set_numbers)
                             .group(:pool_set)
                             .minimum(:created_at)

    sets_data = published.map do |set_number, count|
      best_attempt = user_bests[set_number]
      user_attempt_data = if best_attempt
                            {
                              attempt_id: best_attempt.id,
                              total_score: best_attempt.total_score,
                              max_possible_score: best_attempt.max_possible_score,
                              accuracy_percent: best_attempt.accuracy_percent,
                              percentile: best_attempt.percentile,
                            }
                          end

      set_difficulties = difficulties_by_set.each_with_object({}) do |((ps, diff), cnt), h|
        h[diff] = cnt if ps == set_number
      end
      primary_difficulty = set_difficulties.max_by { |_, v| v }&.first || "mixed"

      set_date = labels_by_set[set_number]
      label = if set_date
                "#{set_date.strftime("%d-%m")}-#{Digest::MD5.hexdigest("#{@template.id}-#{set_number}")[0, 3]}"
              else
                "Set #{set_number}"
              end

      {
        set_number: set_number,
        label: label,
        question_count: count,
        attempts_count: attempts_by_set[set_number] || 0,
        user_attempted: best_attempt.present?,
        user_attempt_data: user_attempt_data,
        difficulty: primary_difficulty,
        difficulty_breakdown: set_difficulties
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
        policy = MockExamAttemptPolicy.new(current_user, MockExamAttempt)
        render json: {
          total_attempts: current_user.mock_exam_attempts.count,
          completed_attempts: completed,
          best_score: scores.max,
          avg_accuracy: scores.any? ? (scores.sum / scores.size).round(1) : nil,
          streak_days: calculate_streak,
          trend: attempts.first(20).reverse.map do |a|
            { accuracy_percent: a.accuracy_percent, date: a.submitted_at&.to_date }
          end,
          section_accuracy: build_section_accuracy(attempts),
          attempts: attempts.map { |a| dashboard_attempt_json(a) },
          is_premium: current_user.cached_base_subscriber?,
          trial_attempts_remaining: policy.daily_attempts_remaining,
          upgrade_url: new_razorpay_subscription_path
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
      published_sets_count: @published_counts ? (@published_counts[template.id] || 0) : template.published_set_count,
      tag_list: template.tag ? [{ name: template.tag.name, id: template.tag.id, bg_color_hex: template.tag.bg_color_hex }] : []
    }
  end

  def set_template_by_slug
    @template = MockExamTemplate.includes(:tag).find_by!(slug: params[:slug], active: true, published: true)
  end

  def stats_json(stats)
    return unless stats&.sufficient_data?

    {
      total_attempts: stats.total_attempts,
      unique_users: stats.unique_users,
      average_score: stats.average_score,
      median_score: stats.median_score,
      highest_score: stats.highest_score,
      average_accuracy: stats.average_accuracy,
      average_time_seconds: stats.average_time_seconds,
      score_distribution: stats.score_distribution,
      completion_rate: stats.completion_rate
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

    best_attempt_ids = scope
                         .select("DISTINCT ON (user_id, pool_set) id")
                         .order(Arel.sql("user_id, pool_set, total_score DESC NULLS LAST, " \
                                           "EXTRACT(EPOCH FROM (submitted_at - started_at)) ASC NULLS LAST, " \
                                           "submitted_at ASC"))
                         .map(&:id)

    attempts = MockExamAttempt
                 .where(id: best_attempt_ids)
                 .order(total_score: :desc)
                 .order(Arel.sql("EXTRACT(EPOCH FROM (submitted_at - started_at)) ASC NULLS LAST"))
                 .order(submitted_at: :asc)
                 .limit(20)
                 .includes(:user)

    attempts.map do |attempt|
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
        set_label: attempt.pool_set ? @template.set_label(attempt.pool_set) : nil,
        time_taken_seconds: if attempt.submitted_at && attempt.started_at
                              (attempt.submitted_at - attempt.started_at).to_i
                            end
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
      submitted_at: attempt.submitted_at
    }
  end

  def build_section_accuracy(attempts)
    section_data = {}
    attempts.pluck(:section_scores).compact.each do |scores|
      scores.each do |name, data|
        section_data[name] ||= { correct: 0, total: 0 }
        section_data[name][:correct] += data["correct"] || 0
        section_data[name][:total] += (data["correct"] || 0) + (data["wrong"] || 0) + (data["unanswered"] || 0)
      end
    end

    section_data.transform_values do |d|
      d[:total].positive? ? (d[:correct].to_f / d[:total] * 100).round(1) : 0
    end
  end

  def calculate_streak
    dates = current_user.mock_exam_attempts
                        .where("submitted_at >= ?", 90.days.ago)
                        .where.not(submitted_at: nil)
                        .order(submitted_at: :desc)
                        .pluck(Arel.sql("DISTINCT DATE(submitted_at)"))

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
    return false unless current_user
    policy = MockExamAttemptPolicy.new(current_user, MockExamAttempt)
    policy.create?
  rescue Pundit::NotAuthorizedError
    false
  end

  def premium_attempts_remaining
    return nil unless current_user
    policy = MockExamAttemptPolicy.new(current_user, MockExamAttempt)
    policy.daily_attempts_remaining
  end

  def premium_upgrade_url
    return nil if current_user&.cached_base_subscriber?

    "/razorpay_subscriptions/new"
  end
end
