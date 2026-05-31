class MockExamAttemptsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template
  before_action :set_attempt, only: %i[show submit results]

  def create
    authorize MockExamAttempt

    questions = MockExams::AssembleExamService.new(@template, current_user).call

    @attempt = current_user.mock_exam_attempts.build(
      mock_exam_template: @template,
      started_at: Time.current,
      expires_at: Time.current + @template.duration_minutes.minutes,
      questions_source: questions ? :pool : :generated,
      )
    authorize @attempt

    unless @attempt.save
      redirect_to mock_exam_path(slug: @template.slug), alert: @attempt.errors.full_messages.first
      return
    end

    if questions
      questions.each_with_index do |q, idx|
        q.update!(mock_exam_attempt: @attempt, position: idx + 1)
        MockExamResponse.create!(mock_exam_attempt: @attempt, mock_exam_question: q)
      end
    else
      MockExams::GenerateQuestionsWorker.perform_async(@attempt.id)
    end

    redirect_to mock_exam_attempt_path(slug: @template.slug, id: @attempt.id)
  end

  def show
    authorize @attempt

    if @attempt.expired? && @attempt.in_progress?
      @attempt.update!(status: :timed_out, submitted_at: Time.current)
      MockExams::ScoringService.new(@attempt).call
      redirect_to results_mock_exam_attempt_path(slug: @template.slug, id: @attempt.id)
      return
    end

    unless @attempt.in_progress?
      redirect_to results_mock_exam_attempt_path(slug: @template.slug, id: @attempt.id)
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
      redirect_to results_mock_exam_attempt_path(slug: @template.slug, id: @attempt.id)
      return
    end

    time_per_question = params[:time_per_question] || {}
    @attempt.time_per_question = time_per_question if time_per_question.present?
    @attempt.status = :submitted
    @attempt.submitted_at = Time.current
    @attempt.save!

    MockExams::ScoringService.new(@attempt).call

    respond_to do |format|
      format.html { redirect_to results_mock_exam_attempt_path(slug: @template.slug, id: @attempt.id) }
      format.json { render json: { redirect_to: results_mock_exam_attempt_path(slug: @template.slug, id: @attempt.id) } }
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
    @attempt = current_user.mock_exam_attempts.find(params[:id])
  end

  def attempt_json(attempt)
    {
      id: attempt.id,
      status: attempt.status,
      time_remaining_seconds: attempt.time_remaining_seconds,
      questions_source: attempt.questions_source,
      template: {
        title: @template.title,
        total_questions: @template.total_questions,
        duration_minutes: @template.duration_minutes,
        marks_per_correct: @template.marks_per_correct,
        negative_marks_per_wrong: @template.negative_marks_per_wrong,
        has_calculator: @template.has_calculator,
        has_scratchpad: @template.has_scratchpad,
      },
      questions: attempt.mock_exam_questions.order(:position).map { |q| question_json(q) },
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
      time_per_question: attempt.time_per_question,
      questions: attempt.mock_exam_questions.order(:position).map { |q|
        response = attempt.mock_exam_responses.find_by(mock_exam_question: q)
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
      },
    }
  end
end
