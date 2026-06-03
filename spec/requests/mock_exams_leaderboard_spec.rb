require "rails_helper"

RSpec.describe "Mock Exams Leaderboard & Stats" do
  let(:user) { create(:user) }
  let(:template) { create(:mock_exam_template) }

  before { sign_in user }

  describe "GET /mock_exams/:slug/leaderboard" do
    it "returns JSON leaderboard entries" do
      create(:mock_exam_attempt,
             mock_exam_template: template,
             user: user,
             status: :submitted,
             total_score: 15.0,
             max_possible_score: 20.0,
             accuracy_percent: 75.0,
             submitted_at: 1.hour.ago,
             started_at: 2.hours.ago)

      get leaderboard_mock_exam_path(slug: template.slug), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["entries"]).to be_an(Array)
      expect(json["entries"].first["username"]).to eq(user.username)
      expect(json["entries"].first["total_score"].to_f).to eq(15.0)
    end

    it "ranks the faster attempt higher when scores are equal" do
      slower = create(:mock_exam_attempt,
                      mock_exam_template: template,
                      user: create(:user),
                      status: :submitted,
                      total_score: 15.0,
                      accuracy_percent: 75.0,
                      started_at: 90.minutes.ago,
                      submitted_at: 30.minutes.ago) # 60 min

      faster = create(:mock_exam_attempt,
                      mock_exam_template: template,
                      user: create(:user),
                      status: :submitted,
                      total_score: 15.0,
                      accuracy_percent: 75.0,
                      started_at: 50.minutes.ago,
                      submitted_at: 30.minutes.ago) # 20 min

      get leaderboard_mock_exam_path(slug: template.slug),
          headers: { "Accept" => "application/json" }

      ids = response.parsed_body["entries"].pluck("attempt_id")
      expect(ids.index(faster.id)).to be < ids.index(slower.id)
    end

    it "sorts attempts without a completion time last in a score tie" do
      timed = create(:mock_exam_attempt,
                     mock_exam_template: template,
                     user: create(:user),
                     status: :submitted,
                     total_score: 15.0,
                     started_at: 90.minutes.ago,
                     submitted_at: 30.minutes.ago)

      no_time = create(:mock_exam_attempt,
                       mock_exam_template: template,
                       user: create(:user),
                       status: :timed_out,
                       total_score: 15.0,
                       started_at: 50.minutes.ago,
                       submitted_at: nil)

      get leaderboard_mock_exam_path(slug: template.slug),
          headers: { "Accept" => "application/json" }

      ids = response.parsed_body["entries"].pluck("attempt_id")
      expect(ids.index(timed.id)).to be < ids.index(no_time.id)
    end

    it "filters by week" do
      create(:mock_exam_attempt,
             mock_exam_template: template,
             user: user,
             status: :submitted,
             total_score: 10.0,
             submitted_at: 2.days.ago,
             started_at: 2.days.ago - 1.hour)

      old_attempt = create(:mock_exam_attempt,
                           mock_exam_template: template,
                           user: user,
                           status: :submitted,
                           total_score: 5.0,
                           submitted_at: 2.weeks.ago,
                           started_at: 2.weeks.ago - 1.hour)

      get leaderboard_mock_exam_path(slug: template.slug),
          params: { filter: "week" },
          headers: { "Accept" => "application/json" }

      json = response.parsed_body
      ids = json["entries"].pluck("attempt_id")
      expect(ids).not_to include(old_attempt.id)
    end

    it "filters by month" do
      create(:mock_exam_attempt,
             mock_exam_template: template,
             user: user,
             status: :submitted,
             total_score: 10.0,
             submitted_at: 10.days.ago,
             started_at: 10.days.ago - 1.hour)

      get leaderboard_mock_exam_path(slug: template.slug),
          params: { filter: "month" },
          headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["entries"]).to be_an(Array)
    end

    it "deduplicates by user+set, allowing one entry per user per set" do
      # Same user, two different sets — should appear twice
      create(:mock_exam_attempt,
             mock_exam_template: template, user: user, pool_set: 1,
             status: :submitted, total_score: 10.0,
             submitted_at: 1.hour.ago, started_at: 2.hours.ago)
      create(:mock_exam_attempt,
             mock_exam_template: template, user: user, pool_set: 2,
             status: :submitted, total_score: 12.0,
             submitted_at: 1.hour.ago, started_at: 2.hours.ago)
      # Same user, same set (retake) — should NOT produce a duplicate
      create(:mock_exam_attempt,
             mock_exam_template: template, user: user, pool_set: 1,
             status: :submitted, total_score: 8.0,
             submitted_at: 30.minutes.ago, started_at: 1.hour.ago)

      get leaderboard_mock_exam_path(slug: template.slug),
          headers: { "Accept" => "application/json" }

      json = Jresponse.body
      entries = json["entries"]
      user_set_pairs = entries.map { |e| [e["user_id"], e["pool_set"]] }
      expect(user_set_pairs.uniq.length).to eq(user_set_pairs.length)
      expect(entries.length).to eq(2)
      # Best score for set 1 should be 10.0, not 8.0
      set1_entry = entries.find { |e| e["pool_set"] == 1 }
      expect(set1_entry["total_score"]).to eq(10.0)
    end

    it "limits to 20 entries" do
      25.times do |i|
        u = create(:user)
        create(:mock_exam_attempt,
               mock_exam_template: template,
               user: u,
               status: :submitted,
               total_score: i,
               submitted_at: 1.hour.ago,
               started_at: 2.hours.ago)
      end

      get leaderboard_mock_exam_path(slug: template.slug),
          headers: { "Accept" => "application/json" }

      json = response.parsed_body
      expect(json["entries"].length).to be <= 20
    end
  end

  describe "GET /mock_exams/:slug/stats" do
    it "returns stats JSON when stats exist" do
      create(:mock_exam_template_stat,
             mock_exam_template: template,
             total_attempts: 50,
             unique_users: 30,
             section_averages: { "General" => 75.0 },
             difficulty_accuracy: { "easy" => 82.0, "medium" => 60.0, "hard" => 35.0 })

      get stats_mock_exam_path(slug: template.slug),
          headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["total_attempts"]).to eq(50)
      expect(json["section_averages"]).to be_present
      expect(json["difficulty_accuracy"]).to be_present
    end

    it "returns error when no stats exist" do
      get stats_mock_exam_path(slug: template.slug),
          headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["error"]).to be_present
    end
  end

  describe "GET /mock_exams/dashboard" do
    it "returns dashboard JSON for authenticated user" do
      create(:mock_exam_attempt,
             mock_exam_template: template,
             user: user,
             status: :submitted,
             total_score: 15.0,
             max_possible_score: 20.0,
             accuracy_percent: 75.0,
             submitted_at: 1.hour.ago)

      get dashboard_mock_exams_path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["total_attempts"]).to be >= 1
      expect(json["completed_attempts"]).to be >= 1
      expect(json["attempts"]).to be_an(Array)
      expect(json["streak_days"]).to be_a(Integer)
    end

    it "requires authentication" do
      sign_out user
      get dashboard_mock_exams_path

      expect(response).to have_http_status(:redirect)
    end
  end
end
