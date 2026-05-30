class MockExamResponsesController < ApplicationController
  before_action :authenticate_user!

  def create
    attempt = current_user.mock_exam_attempts.find(params[:mock_exam_attempt_id])
    authorize attempt, :show?

    return head(:forbidden) unless attempt.in_progress?

    question = attempt.mock_exam_questions.find(params[:mock_exam_question_id])
    response = attempt.mock_exam_responses.find_or_initialize_by(mock_exam_question: question)

    response.assign_attributes(response_params)

    if response.save
      render json: {
        id: response.id,
        selected_option_key: response.selected_option_key,
        marked_for_review: response.marked_for_review,
        time_spent_seconds: response.time_spent_seconds,
      }
    else
      render json: { errors: response.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    response = MockExamResponse.find(params[:id])
    attempt = response.mock_exam_attempt
    authorize attempt, :show?

    return head(:forbidden) unless attempt.in_progress?

    if response.update(response_params)
      render json: {
        id: response.id,
        selected_option_key: response.selected_option_key,
        marked_for_review: response.marked_for_review,
        time_spent_seconds: response.time_spent_seconds,
      }
    else
      render json: { errors: response.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def response_params
    params.require(:mock_exam_response).permit(:selected_option_key, :marked_for_review, :time_spent_seconds)
  end
end
