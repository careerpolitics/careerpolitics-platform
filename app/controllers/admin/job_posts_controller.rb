module Admin
  class JobPostsController < Admin::ApplicationController
    layout "admin"

    before_action :find_job_post, only: %i[show edit update destroy approve]
    JOB_POST_ALLOWED_PARAMS = %i[
      title
      post_type
      link
      color
      published
      approved
      position
      featured
    ].freeze

    def index
      @job_posts = JobPost.includes(:user)
        .order(created_at: :desc)
        .page(params[:page]).per(50)

      return if params[:search].blank?

      @job_posts = @job_posts.where("job_posts.title ILIKE :search", search: "%#{params[:search]}%")
    end

    def show
    end

    def edit
    end

    def update
      if @job_post.update(job_post_params)
        redirect_to admin_job_posts_path, notice: I18n.t("admin.job_posts_controller.updated")
      else
        render :edit
      end
    end

    def approve
      @job_post.update(approved: true, published: true) unless @job_post.approved?
      redirect_to admin_job_posts_path, notice: "Job post approved and published."
    end

    def destroy
      if @job_post.destroy
        redirect_to admin_job_posts_path, notice: "Job post deleted."
      else
        redirect_to admin_job_posts_path, alert: "Failed to delete job post."
      end
    end

    private

    def find_job_post
      @job_post = JobPost.find(params[:id])
    end

    def job_post_params
      params.require(:job_post).permit(JOB_POST_ALLOWED_PARAMS)
    end
  end
end

