class MockExamAttemptsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template
  before_action :set_attempt, only: %i[show submit results]

  def create
    authorize MockExamAttempt

    selected_set = params[:pool_set].present? ? params[:pool_set].to_i : nil
    service = MockExams::AssembleExamService.new(@template, current_user, pool_set: selected_set)
    questions = service.call

    unless questions
      msg = "No published questions available. Please try a different set or try later."
      respond_to do |format|
        format.html { redirect_to mock_exam_path(slug: @template.slug), alert: msg }
        format.json { render json: { errors: [msg] }, status: :unprocessable_entity }
      end
      return
    end

    @attempt = current_user.mock_exam_attempts.build(
      mock_exam_template: @template,
      started_at: Time.current,
      expires_at: Time.current + @template.duration_minutes.minutes,
      pool_set: service.pool_set || selected_set,
      )
    authorize @attempt

    unless @attempt.save
      respond_to do |format|
        format.html { redirect_to mock_exam_path(slug: @template.slug), alert: @attempt.errors.full_messages.first }
        format.json { render json: { errors: @attempt.errors.full_messages }, status: :unprocessable_entity }
      end
      return
    end

    questions.each do |q|
      q.mock_exam_attempt = @attempt
      q.save!
      MockExamResponse.create!(mock_exam_attempt: @attempt, mock_exam_question: q)
    end

    respond_to do |format|
      format.html { redirect_to mock_exam_attempt_path(mock_exam_slug: @template.slug, id: @attempt.id) }
      format.json do
        render json: { id: @attempt.id,
                       redirect_to: "/mock_exams/#{@template.slug}/attempts/#{@attempt.id}" }
      end
    end
  end

  def show
    authorize @attempt

    if @attempt.expired? && @attempt.in_progress?
      @attempt.update!(status: :timed_out, submitted_at: Time.current)
      MockExams::ScoringService.new(@attempt).call
      redirect_to results_mock_exam_attempt_path(mock_exam_slug: @template.slug, id: @attempt.id)
      return
    end

    unless @attempt.in_progress?
      redirect_to results_mock_exam_attempt_path(mock_exam_slug: @template.slug, id: @attempt.id)
      return
    end

    respond_to do |format|
      format.html
      format.json do
        render json: attempt_json(@attempt)
      end
    end
  end

  def submit
    authorize @attempt

    unless @attempt.in_progress?
      redirect_to results_mock_exam_attempt_path(mock_exam_slug: @template.slug, id: @attempt.id)
      return
    end

    time_per_question = params[:time_per_question] || {}
    @attempt.time_per_question = time_per_question if time_per_question.present?
    @attempt.status = :submitted
    @attempt.submitted_at = Time.current
    @attempt.save!

    MockExams::ScoringService.new(@attempt).call

    respond_to do |format|
      format.html { redirect_to results_mock_exam_attempt_path(mock_exam_slug: @template.slug, id: @attempt.id) }
      format.json { render json: { redirect_to: results_mock_exam_attempt_path(mock_exam_slug: @template.slug, id: @attempt.id) } }
    end
  end

  def results
    authorize @attempt

    respond_to do |format|
      format.html
      format.json do
        render json: results_json(@attempt)
      end
    end
  end

  private

  def set_template
    @template = MockExamTemplate.find_by!(slug: params[:mock_exam_slug], active: true, published: true)
  end

  def set_attempt
    @attempt = current_user.mock_exam_attempts
                           .includes(:mock_exam_questions, :mock_exam_responses)
                           .find(params[:id])
  end

  def attempt_json(attempt)
    {
      id: attempt.id,
      status: attempt.status,
      time_remaining_seconds: attempt.time_remaining_seconds,
      template: {
        title: @template.title,
        total_questions: @template.total_questions,
        duration_minutes: @template.duration_minutes,
        marks_per_correct: @template.marks_per_correct,
        negative_marks_per_wrong: @template.negative_marks_per_wrong,
        has_calculator: @template.has_calculator,
        has_scratchpad: @template.has_scratchpad,
        sections_config: @template.sections_config,
        question_display_mode: @template.question_display_mode,
      },
      questions: attempt.mock_exam_questions.sort_by(&:position).map { |q| question_json(q) },
      responses: attempt.mock_exam_responses.index_by(&:mock_exam_question_id).transform_values { |r|
        {
          id: r.id,
          selected_option_key: r.selected_option_key,
          marked_for_review: r.marked_for_review,
          time_spent_seconds: r.time_spent_seconds,
        }
      },
    }
  end

  def question_json(question)
    {
      id: question.id,
      position: question.position,
      section_name: question.section_name,
      question_type: question.question_type,
      question_format: question.question_format,
      question_text: question.question_text,
      question_html: question.question_html,
      question_svg: question.question_svg,
      text_hi: question.text_hi,
      options: question.options,
    }
  end

  def results_json(attempt)
    {
      id: attempt.id,
      user_id: attempt.user_id,
      status: attempt.status,
      total_score: attempt.total_score,
      max_possible_score: attempt.max_possible_score,
      correct_count: attempt.correct_count,
      incorrect_count: attempt.incorrect_count,
      unanswered_count: attempt.unanswered_count,
      total_questions: attempt.total_questions,
      accuracy_percent: attempt.accuracy_percent,
      percentile: attempt.percentile,
      rank: attempt.rank,
      avg_time_per_question: attempt.avg_time_per_question,
      section_scores: attempt.section_scores,
      difficulty_breakdown: build_difficulty_breakdown(attempt),
      time_per_question: attempt.time_per_question,
      questions: begin
                   responses_by_qid = attempt.mock_exam_responses.index_by(&:mock_exam_question_id)
                   attempt.mock_exam_questions.sort_by(&:position).map { |q|
                     response = responses_by_qid[q.id]
                     question_json(q).merge(
                       correct_option_key: q.correct_option_key,
                       explanation: q.explanation,
                       explanation_html: q.explanation_html,
                       explanation_hi: q.explanation_hi,
                       solution_steps: q.solution_steps,
                       solution_steps_html: q.solution_steps_html,
                       difficulty: q.difficulty,
                       selected_option_key: response&.selected_option_key,
                       is_correct: response&.is_correct,
                       time_spent_seconds: response&.time_spent_seconds,
                       )
                   }
                 end,
    }
  end

  def build_difficulty_breakdown(attempt)
    responses = attempt.mock_exam_responses.includes(:mock_exam_question).where.not(selected_option_key: nil)
    result = {}
    %w[easy medium hard].each do |diff|
      diff_responses = responses.select { |r| r.mock_exam_question.difficulty == diff }
      total = diff_responses.size
      correct = diff_responses.count(&:correct?)
      result[diff] = total.positive? ? (correct.to_f / total * 100).round(1) : 0
    end
    result
  end
end
