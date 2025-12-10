class JobPostsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_job_post, only: %i[show edit update]
  after_action :verify_authorized, except: %i[index show]

  def index
    @featured_job_posts = JobPost.featured
    @new_updates = JobPost.published.by_post_type('new_update').recent.limit(10)
    @admit_cards = JobPost.published.by_post_type('admit_card').recent.limit(10)
    @online_forms = JobPost.published.by_post_type('online_form').recent.limit(10)
  end

  def show
    @job_post = JobPost.find_by!(slug: params[:slug] || params[:id])
  end

  def new
    @job_post = JobPost.new
    authorize @job_post
  end

  def create
    @job_post = current_user.job_posts.build(job_post_params)
    authorize @job_post

    if @job_post.save
      redirect_to job_post_path(@job_post.slug), notice: 'Job post created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @job_post
  end

  def update
    authorize @job_post

    if @job_post.update(job_post_params)
      redirect_to job_post_path(@job_post.slug), notice: 'Job post updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_job_post
    @job_post = JobPost.find_by!(slug: params[:slug] || params[:id])
  end

  def job_post_params
    params.require(:job_post).permit(:title, :description, :category, :post_type, :link, :color, :published)
  end
end
