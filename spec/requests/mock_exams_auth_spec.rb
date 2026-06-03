require "rails_helper"

RSpec.describe "Mock Exams Authentication", type: :request do
  let(:template) { create(:mock_exam_template) }

  describe "unauthenticated user" do
    it "can view mock exams index page" do
      get mock_exams_path
      expect(response).to have_http_status(:ok)
    end

    it "can view mock exam detail page" do
      get mock_exam_path(slug: template.slug)
      expect(response).to have_http_status(:ok)
    end

    it "receives can_attempt: false and user_signed_in: false in JSON", :aggregate_failures do
      get mock_exam_path(slug: template.slug), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["can_attempt"]).to be false
      expect(json["user_signed_in"]).to be false
    end

    it "is redirected when trying to create an attempt" do
      post "/mock_exams/#{template.slug}/attempts",
           params: { pool_set: 1 },
           headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:redirect)
    end

    it "is blocked from dashboard" do
      get dashboard_mock_exams_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "authenticated user" do
    let(:user) { create(:user) }

    before { sign_in user }

    it "receives can_attempt: true and user_signed_in: true in JSON", :aggregate_failures do
      get mock_exam_path(slug: template.slug), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["can_attempt"]).to be true
      expect(json["user_signed_in"]).to be true
    end

    it "can access dashboard" do
      get dashboard_mock_exams_path
      expect(response).to have_http_status(:ok)
    end
  end
end
