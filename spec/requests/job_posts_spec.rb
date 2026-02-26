require 'rails_helper'

RSpec.describe "JobPosts", type: :request do
  describe "GET /jobs" do
    it "returns success and section entries link directly to application urls" do
      job_one = create(:job_post, post_type: "new_update", link: "https://external.example/new-update", featured: false)
      job_two = create(:job_post, post_type: "admit_card", link: "https://external.example/admit-card", featured: false)
      job_three = create(:job_post, post_type: "online_form", link: "https://external.example/online-form", featured: false)

      get job_posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Latest Government Job Updates - CareerPolitics")
      expect(response.body).to include("Discover the latest government job updates")
      expect(response.body).to include("https://external.example/new-update")
      expect(response.body).to include("https://external.example/admit-card")
      expect(response.body).to include("https://external.example/online-form")
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
      expect(get: "/jobs/upsc-assistant-recruitment-2026").not_to be_routable
    end
  end
end
