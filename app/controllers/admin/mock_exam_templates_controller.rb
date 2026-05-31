module Admin
  class MockExamTemplatesController < Admin::ApplicationController
    layout "admin"

    def index
      @templates = MockExamTemplate.order(created_at: :desc)
    end

    def show
      @template = MockExamTemplate.find(params[:id])
      @pool_count = @template.pool_questions.count
      @available_sets = @template.available_sets
      @stats = @template.mock_exam_template_stat
      @recent_attempts = @template.mock_exam_attempts
                                  .includes(:user)
                                  .order(created_at: :desc)
                                  .limit(20)
    end

    def review_set
      @template = MockExamTemplate.find(params[:id])
      @set_number = params[:set].to_i
      @questions = @template.set_questions(@set_number)
      @is_published = @template.set_published?(@set_number)
    end

    def publish_set
      @template = MockExamTemplate.find(params[:id])
      set_number = params[:set].to_i
      @template.set_questions(set_number).update_all(set_published: true)
      redirect_to review_set_admin_mock_exam_template_path(@template, set: set_number),
                  notice: "Set #{set_number} published successfully."
    end

    def unpublish_set
      @template = MockExamTemplate.find(params[:id])
      set_number = params[:set].to_i
      @template.set_questions(set_number).update_all(set_published: false)
      redirect_to review_set_admin_mock_exam_template_path(@template, set: set_number),
                  notice: "Set #{set_number} unpublished."
    end

    def edit_question
      @template = MockExamTemplate.find(params[:id])
      @question = @template.pool_questions.find(params[:question_id])
    end

    def update_question
      @template = MockExamTemplate.find(params[:id])
      @question = @template.pool_questions.find(params[:question_id])
      if @question.update(question_params)
        redirect_to review_set_admin_mock_exam_template_path(@template, set: @question.pool_set),
                    notice: "Question updated."
      else
        render :edit_question
      end
    end

    def destroy_question
      @template = MockExamTemplate.find(params[:id])
      @question = @template.pool_questions.find(params[:question_id])
      set_number = @question.pool_set
      @question.destroy!
      redirect_to review_set_admin_mock_exam_template_path(@template, set: set_number),
                  notice: "Question deleted."
    end

    def new
      @template = MockExamTemplate.new
    end

    def create
      @template = MockExamTemplate.new(template_params)
      @template.created_by = current_user
      if @template.save
        redirect_to admin_mock_exam_template_path(@template), notice: "Template created successfully."
      else
        render :new
      end
    end

    def edit
      @template = MockExamTemplate.find(params[:id])
    end

    def update
      @template = MockExamTemplate.find(params[:id])
      if @template.update(template_params)
        redirect_to admin_mock_exam_template_path(@template), notice: "Template updated successfully."
      else
        render :edit
      end
    end

    def destroy
      @template = MockExamTemplate.find(params[:id])
      @template.destroy!
      redirect_to admin_mock_exam_templates_path, notice: "Template deleted."
    end

    def generate_pool
      @template = MockExamTemplate.find(params[:id])
      MockExams::GeneratePoolWorker.perform_async(@template.id)
      redirect_to admin_mock_exam_template_path(@template),
                  notice: "Pool generation started. Questions will appear in a few minutes."
    end

    def refresh_pool
      @template = MockExamTemplate.find(params[:id])
      @template.pool_questions.where(set_published: false).destroy_all
      MockExams::GeneratePoolWorker.perform_async(@template.id)
      redirect_to admin_mock_exam_template_path(@template),
                  notice: "Unpublished questions cleared and new sets being generated. Published sets are preserved."
    end

    private

    def question_params
      permitted = params.require(:mock_exam_question).permit(
        :question_text, :correct_option_key, :explanation,
        :solution_steps, :difficulty, :section_name, :question_type,
        )
      if params[:mock_exam_question][:options].present?
        permitted[:options] = params[:mock_exam_question][:options].map do |opt|
          { "key" => opt[:key], "text" => opt[:text] }
        end
      end
      permitted
    end

    def template_params
      permitted = params.require(:mock_exam_template).permit(
        :title, :slug, :description, :exam_category, :total_questions,
        :duration_minutes, :marks_per_correct, :negative_marks_per_wrong,
        :question_display_mode, :difficulty_level, :ai_prompt_context,
        :has_calculator, :has_scratchpad, :active, :published,
        :sections_config,
        )

      if permitted[:sections_config].is_a?(String)
        permitted[:sections_config] = JSON.parse(permitted[:sections_config])
      end

      permitted
    rescue JSON::ParserError
      permitted
    end
  end
end
