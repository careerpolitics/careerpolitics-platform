require 'rails_helper'

RSpec.describe "JobPosts", type: :request do
  describe "GET /jobs" do
    it "returns success and section entries link directly to application urls" do
      create(:job_post, post_type: "new_update", link: "https://external.example/new-update", featured: false)
      create(:job_post, post_type: "admit_card", link: "https://external.example/admit-card", featured: false)
      create(:job_post, post_type: "online_form", link: "https://external.example/online-form", featured: false)

      get job_posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Latest Government Job Updates - CareerPolitics")
      expect(response.body).to include("Discover the latest government job updates")
      expect(response.body).to include("https://external.example/new-update")
      expect(response.body).to include("https://external.example/admit-card")
      expect(response.body).to include("https://external.example/online-form")
      expect(response.body).to include("Organization")
      expect(response.body).to include("Total Posts")
      expect(response.body).to include("Qualification")
      expect(response.body).to include("Last Date")
      expect(response.body).to include("Exam Date")
    end
  end

  describe "legacy scaffold routes" do
    it "are no longer routable" do
      expect(get: "/job_posts/index").not_to be_routable
      expect(get: "/job_posts/show").not_to be_routable
      expect(get: "/job_posts/new").not_to be_routable
      expect(get: "/job_posts/create").not_to be_routable
      expect(get: "/job_posts/edit").not_to be_routable
      expect(get: "/job_posts/update").not_to be_routable
      expect(get: "/jobs/type/new_update").not_to be_routable
    end
  end

  describe "GET /jobs/:slug" do
    it "renders a public job details page" do
      job_post = create(:job_post, title: "Public role", slug: "public-role")

      get job_post_path(job_post.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Public role")
      expect(response.body).to include("Application Link")
    end
  end
end
