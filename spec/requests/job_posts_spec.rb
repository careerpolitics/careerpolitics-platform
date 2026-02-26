require 'rails_helper'

RSpec.describe "JobPosts", type: :request do
  describe "GET /jobs" do
    it "returns success with index metadata and hub links" do
      create(:job_post, featured: true)

      get job_posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Latest Government Job Updates - CareerPolitics")
      expect(response.body).to include("Discover the latest government job updates")
      expect(response.body).to include(type_job_posts_path("new_update"))
      expect(response.body).to include(type_job_posts_path("admit_card"))
      expect(response.body).to include(type_job_posts_path("online_form"))
    end
  end

  describe "GET /jobs/:slug" do
    it "renders canonical detail page with metadata and server-side JSON-LD" do
      job_post = create(
        :job_post,
        title: "UPSC Assistant Recruitment 2026",
        link: "https://example.com/apply",
        organization_name: "UPSC",
        location: "Delhi",
        employment_type: "full_time",
        deadline_at: 2.months.from_now,
        qualification: "Graduate degree",
      )

      get job_post_path(job_post.slug)

      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      expect(response.body).to include("UPSC Assistant Recruitment 2026")
      expect(response.body).to include("<meta property=\"og:type\" content=\"article\">")
      expect(response.body).to include("application/ld+json")
      expect(response.body).to include("\"@type\":\"JobPosting\"")
      expect(response.body).to include("\"@type\":\"BreadcrumbList\"")
    end
  end

  describe "GET /jobs/type/:post_type" do
    it "renders post type hub page without authentication" do
      create(:job_post, post_type: "admit_card", title: "SSC Admit Card 2026")

      get type_job_posts_path("admit_card")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SSC Admit Card 2026")
      expect(response.body).to include("Admit card Job Updates")
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
