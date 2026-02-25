require 'rails_helper'

RSpec.describe "JobPosts", type: :request do
  describe "GET /jobs" do
    it "returns success with index metadata" do
      create(:job_post, featured: true)

      get job_posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Latest Government Job Updates - CareerPolitics")
      expect(response.body).to include("Discover the latest government job updates")
      expect(response.body).to include("<main class=\"jobs-page\">")
    end
  end

  describe "GET /jobs/:slug" do
    it "renders canonical detail page with metadata" do
      job_post = create(:job_post, title: "UPSC Assistant Recruitment 2026", link: "https://example.com/apply")

      get job_post_path(job_post.slug)

      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      expect(response.body).to include("UPSC Assistant Recruitment 2026")
      expect(response.body).to include("<meta property=\"og:type\" content=\"article\">")
      expect(response.body).to include("Application Link:")
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
    end
  end
end
