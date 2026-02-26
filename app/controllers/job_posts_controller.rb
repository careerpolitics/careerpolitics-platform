class JobPostsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_job_post, only: %i[show edit update]
  after_action :verify_authorized, except: %i[index show]

  def index
    @featured_job_posts = JobPost.featured.includes(:user)
    
    # Paginate each section with 10 items per page
    @new_updates = JobPost.available.by_post_type('new_update').includes(:user).recent.page(params[:new_updates_page] || 1).per(10)
    @admit_cards = JobPost.available.by_post_type('admit_card').includes(:user).recent.page(params[:admit_cards_page] || 1).per(10)
    @online_forms = JobPost.available.by_post_type('online_form').includes(:user).recent.page(params[:online_forms_page] || 1).per(10)
    
    respond_to do |format|
      format.html
      format.json do
        post_type = params[:post_type]
        page = params[:page] || 1
        
        job_posts = case post_type
                    when 'new_update'
                      JobPost.available.by_post_type('new_update').includes(:user).recent.page(page).per(10)
                    when 'admit_card'
                      JobPost.available.by_post_type('admit_card').includes(:user).recent.page(page).per(10)
                    when 'online_form'
                      JobPost.available.by_post_type('online_form').includes(:user).recent.page(page).per(10)
                    else
                      JobPost.none.page(1)
                    end
        
        render json: {
          job_posts: job_posts.map { |jp| job_post_json(jp) },
          has_next_page: job_posts.next_page.present?,
          next_page: job_posts.next_page,
          current_page: job_posts.current_page,
          total_pages: job_posts.total_pages
        }
      end
    end
  end


  def show
    @job_post = JobPost.find_by!(slug: params[:slug] || params[:id])
    @related_jobs = @job_post.related_jobs
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
    params.require(:job_post).permit(:title, :post_type, :category, :link, :color, :organization_name, :location,
                                     :deadline_at, :employment_type, :salary_range, :qualification, :vacancies,
                                     :source_name, :source_url, :important_dates)
  end


  def job_post_json(job_post)
    {
      id: job_post.id,
      title: job_post.title,
      link: job_post_path(job_post.slug),
      badge_type: job_post.badge_type,
      post_type: job_post.post_type,
      qualification: job_post.qualification&.truncate(80),
      deadline_at: job_post.deadline_at&.to_date&.to_s
    }
  end
end
