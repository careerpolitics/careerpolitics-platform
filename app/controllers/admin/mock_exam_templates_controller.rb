module Admin
  class MockExamTemplatesController < Admin::ApplicationController
    layout "admin"
    before_action :set_tags, only: %i[new create edit update]

    def index
      @templates = MockExamTemplate.order(created_at: :desc)
    end

    def show
      @template = MockExamTemplate.includes(:tag).find(params[:id])
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

    def destroy_set
      @template = MockExamTemplate.find(params[:id])
      set_number = params[:set].to_i
      label = @template.set_label(set_number)
      @template.set_questions(set_number).destroy_all
      redirect_to admin_mock_exam_template_path(@template),
                  notice: "Set #{label} (#{set_number}) deleted."
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
      sets = (params[:sets_count].presence || 3).to_i.clamp(1, 20)
      MockExams::GeneratePoolWorker.perform_async(@template.id, sets)
      redirect_to admin_mock_exam_template_path(@template),
                  notice: "Generating #{sets} new sets. Questions will appear in a few minutes."
    end

    def refresh_pool
      @template = MockExamTemplate.find(params[:id])
      @template.pool_questions.where(set_published: false).destroy_all
      sets = (params[:sets_count].presence || 3).to_i.clamp(1, 20)
      MockExams::GeneratePoolWorker.perform_async(@template.id, sets)
      redirect_to admin_mock_exam_template_path(@template),
                  notice: "Unpublished questions cleared and new sets being generated. Published sets are preserved."
    end

    def translate_pool
      @template = MockExamTemplate.find(params[:id])
      untranslated = @template.pool_questions.where(text_hi: nil).count
      if untranslated.zero?
        redirect_to admin_mock_exam_template_path(@template),
                    notice: "All pool questions are already translated to Hindi."
      else
        MockExams::TranslatePoolWorker.perform_async(@template.id)
        redirect_to admin_mock_exam_template_path(@template),
                    notice: "Translating #{untranslated} questions to Hindi. This may take a few minutes."
      end
    end

    def backfill_set
      @template = MockExamTemplate.find(params[:id])
      set_number = params[:set].to_i
      existing_by_section = @template.pool_questions
                                     .where(pool_set: set_number)
                                     .group(:section_name)
                                     .count

      shortfalls = @template.sections_config.filter_map do |section|
        have = existing_by_section[section["name"]] || 0
        need = section["count"] - have
        next if need <= 0

        { "name" => section["name"], "type" => section["type"], "count" => need, "topics" => section["topics"] }
      end

      if shortfalls.empty?
        redirect_to review_set_admin_mock_exam_template_path(@template, set: set_number),
                    notice: "Set #{set_number} is already complete."
      else
        total_needed = shortfalls.sum { |s| s["count"] }
        MockExams::BackfillSetWorker.perform_async(@template.id, set_number, shortfalls)
        redirect_to admin_mock_exam_template_path(@template),
                    notice: "Backfilling #{total_needed} questions for Set #{set_number}. This may take a few minutes."
      end
    end

    def regenerate_section
      @template = MockExamTemplate.find(params[:id])
      section_name = params[:section]
      section_config = @template.sections_config.find { |s| s["name"] == section_name }

      unless section_config
        redirect_to admin_mock_exam_template_path(@template), alert: "Section '#{section_name}' not found."
        return
      end

      unpublished = @template.pool_questions.where(section_name: section_name, set_published: false)
      deleted = unpublished.count
      unpublished.destroy_all

      MockExams::RegenerateSectionWorker.perform_async(
        @template.id, section_name, section_config["type"],
        section_config["count"], section_config["topics"],
        )
      redirect_to admin_mock_exam_template_path(@template),
                  notice: "Regenerating '#{section_name}' (deleted #{deleted} old questions). New questions will appear shortly."
    end

    def new_question
      @template = MockExamTemplate.find(params[:id])
      @set_number = params[:set].to_i
      @question = MockExamQuestion.new(
        mock_exam_template: @template,
        pool_set: @set_number,
        position: @template.set_questions(@set_number).maximum(:position).to_i + 1,
        )
    end

    def create_question
      @template = MockExamTemplate.find(params[:id])
      @question = @template.mock_exam_questions.build(question_params)
      @question.pool_set = params[:mock_exam_question][:pool_set].to_i
      @question.position = @template.set_questions(@question.pool_set).maximum(:position).to_i + 1
      @question.ai_generation_metadata = { source: "manual", created_by: current_user.id }

      if @question.save
        redirect_to review_set_admin_mock_exam_template_path(@template, set: @question.pool_set),
                    notice: "Question added to Set #{@question.pool_set}."
      else
        @set_number = @question.pool_set
        render :new_question
      end
    end

    def retranslate_question
      @template = MockExamTemplate.find(params[:id])
      @question = @template.pool_questions.find(params[:question_id])
      @question.update_columns(text_hi: nil, explanation_hi: nil)
      MockExams::TranslatePoolWorker.perform_async(@template.id)
      redirect_to review_set_admin_mock_exam_template_path(@template, set: @question.pool_set),
                  notice: "Re-translating question ##{@question.id}. Translation will update shortly."
    end

    def clone_to_set
      @template = MockExamTemplate.find(params[:id])
      source = @template.pool_questions.find(params[:question_id])
      target_set = params[:target_set].to_i

      clone = source.dup
      clone.pool_set = target_set
      clone.set_published = false
      clone.position = @template.set_questions(target_set).maximum(:position).to_i + 1
      clone.times_served = 0
      clone.ai_generation_metadata = (source.ai_generation_metadata || {}).merge(
        "cloned_from" => source.id, "cloned_at" => Time.current.iso8601,
        )
      clone.save!

      redirect_to review_set_admin_mock_exam_template_path(@template, set: target_set),
                  notice: "Question cloned to Set #{target_set}."
    end

    def diagnostics
      @template = MockExamTemplate.find(params[:id])
      @sets_data = @template.available_sets

      @set_details = @sets_data.keys.sort.map do |set_num|
        questions = @template.set_questions(set_num)
        existing_by_section = existing.unscope(:order).group(:section_name).count

        sections = @template.sections_config.map do |sc|
          have = by_section[sc["name"]] || 0
          { name: sc["name"], expected: sc["count"], actual: have, shortfall: sc["count"] - have }
        end

        {
          set: set_num,
          total: questions.count,
          expected: @template.total_questions,
          published: @template.set_published?(set_num),
          sections: sections,
        }
      end

      @translation_status = {
        total: @template.pool_questions.count,
        translated: @template.pool_questions.where.not(text_hi: nil).count,
        pending: @template.pool_questions.where(text_hi: nil).count,
      }
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

    def set_tags
      subforem = RequestStore.store[:subforem]
      if subforem
        supported_ids = subforem.tag_relationships.where(supported: true).pluck(:tag_id)
        @tags = Tag.where(id: supported_ids).order(:name)
      else
        @tags = Tag.where(supported: true).order(:name)
      end
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

      tag_name = params[:mock_exam_template][:tag_name].presence
      if tag_name
        tag = Tag.find_by(name: tag_name.strip.downcase)
        permitted[:tag_id] = tag&.id
      end

      permitted
    rescue JSON::ParserError
      permitted
    end
  end
end
