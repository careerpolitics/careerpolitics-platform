require 'rails_helper'

RSpec.describe "JobPosts", type: :request do
  describe "GET /jobs" do
    it "returns success and section entries link to internal detail pages" do
      job_one = create(:job_post, post_type: "new_update", link: "https://external.example/new-update", featured: false)
      job_two = create(:job_post, post_type: "admit_card", link: "https://external.example/admit-card", featured: false)
      job_three = create(:job_post, post_type: "online_form", link: "https://external.example/online-form", featured: false)

      get job_posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Latest Government Job Updates - CareerPolitics")
      expect(response.body).to include("Discover the latest government job updates")
      expect(response.body).to include(job_post_path(job_one.slug))
      expect(response.body).to include(job_post_path(job_two.slug))
      expect(response.body).to include(job_post_path(job_three.slug))
    end
  end

  describe "GET /jobs/:slug" do
    it "renders detail page with hidden seo fields and apply link" do
      job_post = create(:job_post, title: "BSF Constable 2026", organization_name: "BSF", vacancies: 120, salary_range: "₹25,500 - ₹81,100", link: "https://example.com/apply")

      get job_post_path(job_post.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("BSF Constable 2026")
      expect(response.body).to include("application/ld+json")
      expect(response.body).to include("BSF")
      expect(response.body).to include("₹25,500 - ₹81,100")
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
end
