require 'rails_helper'

RSpec.describe "JobPosts", type: :request do
  describe "POST /jobs" do
    let(:user) { create(:user) }
    let(:job_post_params) do
      {
        title: "UP Polytechnic JEECUP Online Form 2026",
        description: "Official notification for JEECUP online form.",
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
      expect(created_job_post.description).to eq("Official notification for JEECUP online form.")
      expect(created_job_post.published).to be(false)
      expect(created_job_post.approved).to be(false)
    end
  end

  describe "GET /jobs/new" do
    let(:user) { create(:user) }

    it "shows Result as post type option" do
      sign_in(user)

      get new_job_post_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Result")
    end
  end

  describe "GET /jobs" do
    it "returns success and section entries are crawlable internal urls" do
      create(:job_post, post_type: "new_update", link: "/the_cp_team/new-update", featured: false)
      create(:job_post, post_type: "admit_card", link: "/the_cp_team/admit-card", featured: false)
      create(:job_post, post_type: "online_form", link: "/the_cp_team/online-form", featured: false)

      get job_posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Latest Government Job Updates - CareerPolitics")
      expect(response.body).to include("Discover the latest government job updates")
      expect(response.body).to include("/the_cp_team/new-update")
      expect(response.body).to include("/the_cp_team/admit-card")
      expect(response.body).to include("/the_cp_team/online-form")
      expect(response.body).to include("Organization")
      expect(response.body).to include("Total Posts")
      expect(response.body).to include("Qualification")
      expect(response.body).to include("Last Date")
      expect(response.body).to include("Exam Date")
    end

    it "renders JobPosting json-ld with description from linked internal article" do
      article = create(:article, path: "/the_cp_team/ssc-notice", description: "Government recruitment notice", score: 10)
      create(:job_post,
             post_type: "new_update",
             title: "Staff Selection Notice",
             organization_name: "SSC",
             location: "New Delhi",
             link: article.path,
             salary_range: "50000",
             employment_type: "full_time",
             deadline_at: 1.month.from_now)

      get job_posts_path

      expect(response.body).to include('"@type":"JobPosting"')
      expect(response.body).to include('"hiringOrganization":{"@type":"Organization","name":"SSC"}')
      expect(response.body).to include('"jobLocation":{"@type":"Place"')
      expect(response.body).to include('"description":"Government recruitment notice"')
      expect(response.body).to include('"datePosted":')
      expect(response.body).to include('"employmentType":"FULL_TIME"')
      expect(response.body).to include('"validThrough":')
      expect(response.body).to include('"baseSalary":{"@type":"MonetaryAmount"')
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
