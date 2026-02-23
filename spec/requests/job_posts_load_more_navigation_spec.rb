require "rails_helper"

RSpec.describe "Job posts load more navigation", type: :request do
  let(:user) { create(:user) }

  before do
    create_list(:job_post, 11, user: user, post_type: "new_update", published: true, approved: true, link: "/jobs/new-update")
    create_list(:job_post, 11, user: user, post_type: "admit_card", published: true, approved: true, link: "/jobs/admit-card")
    create_list(:job_post, 11, user: user, post_type: "online_form", published: true, approved: true, link: "/jobs/online-form")
  end

  it "renders load more links to category pages instead of expansion buttons" do
    get job_posts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(job_posts_path(post_type: "new_update", page: 2))
    expect(response.body).to include(job_posts_path(post_type: "admit_card", page: 2))
    expect(response.body).to include(job_posts_path(post_type: "online_form", page: 2))
  end

  it "renders a dedicated category page when post_type is passed" do
    target_post = create(:job_post, user: user, title: "Category Only", post_type: "online_form", published: true, approved: true, link: "/jobs/category-only")

    get job_posts_path(post_type: "online_form", page: 1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Top Online Form")
    expect(response.body).to include(target_post.title)
    expect(response.body).to include(job_posts_path)
  end
end
