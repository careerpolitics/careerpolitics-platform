require 'rails_helper'

RSpec.describe "JobPosts", type: :request do
  describe "POST /jobs" do
    let(:user) { create(:user) }
    let(:job_post_params) do
      {
        title: "UP Polytechnic JEECUP Online Form 2026",
        post_type: "online_form",
        organization_name: "Polytechnic",
        location: "UP",
        deadline_at: "2026-04-30T22:53",
        employment_type: "full_time",
        qualification: "10th",
        link: "/the_cp_team/up-polytechnic-jeecup-online-form-2026-1473",
        color: "#0bac68"
      }
    end

    it "creates a job post for the signed-in user" do
      sign_in(user)

      expect do
        post job_posts_path, params: { job_post: job_post_params }
      end.to change(JobPost, :count).by(1)

      created_job_post = JobPost.last
      expect(response).to redirect_to(job_posts_path)
      expect(created_job_post.user).to eq(user)
      expect(created_job_post.published).to be(false)
      expect(created_job_post.approved).to be(false)
    end
  end

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
      expect(get: "/jobs/upsc-assistant-recruitment-2026").not_to be_routable
    end
  end
end
