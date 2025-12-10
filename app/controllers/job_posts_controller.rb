class JobPostsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_job_post, only: %i[show edit update]
  after_action :verify_authorized, except: %i[index show]

  def index
    @featured_job_posts = JobPost.featured
    @new_updates = JobPost.available.by_post_type('new_update').recent.limit(10)
    @admit_cards = JobPost.available.by_post_type('admit_card').recent.limit(10)
    @online_forms = JobPost.available.by_post_type('online_form').recent.limit(10)
  end

  def show
    @job_post = JobPost.find_by!(slug: params[:slug] || params[:id])
    return unless @job_post
    
    @related_jobs = @job_post.related_jobs
    
    # Only redirect if link is an absolute external URL
    if @job_post.link.present? && @job_post.link.match?(/\Ahttps?:\/\//)
      redirect_to @job_post.link, allow_other_host: true
    end
    # Otherwise render the show page (for relative URLs or no link)
  end

  def new
    @job_post = JobPost.new
    authorize @job_post
  end

  def create
    @job_post = current_user.job_posts.build(job_post_params)
    authorize @job_post

    # New job posts are not published or approved by default
    @job_post.published = false
    @job_post.approved = false

    if @job_post.save
      flash[:global_notice] = 'Job post submitted successfully. It will be reviewed and published by an admin.'
      redirect_to job_posts_path
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
      redirect_to job_posts_path, notice: 'Job post updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_job_post
    @job_post = JobPost.find_by!(slug: params[:slug] || params[:id])
  end

  def job_post_params
    params.require(:job_post).permit(:title, :post_type, :link, :color)
  end
end
