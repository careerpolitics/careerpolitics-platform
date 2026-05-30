module Admin
  class MockExamTemplatesController < Admin::ApplicationController
    layout "admin"

    def index
      @templates = MockExamTemplate.order(created_at: :desc)
    end

    def show
      @template = MockExamTemplate.find(params[:id])
      @pool_count = @template.pool_questions.count
      @stats = @template.mock_exam_template_stat
      @recent_attempts = @template.mock_exam_attempts
                                  .includes(:user)
                                  .order(created_at: :desc)
                                  .limit(20)
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
      @template.pool_questions.destroy_all
      MockExams::GeneratePoolWorker.perform_async(@template.id)
      redirect_to admin_mock_exam_template_path(@template),
                  notice: "Pool cleared and regeneration started."
    end

    private

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
