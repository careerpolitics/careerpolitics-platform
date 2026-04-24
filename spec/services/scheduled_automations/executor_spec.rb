require "rails_helper"

RSpec.describe ScheduledAutomations::Executor, type: :service do
  let(:bot) { create(:user, type_of: :community_bot) }
  let(:automation) do
    create(:scheduled_automation,
           user: bot,
           service_name: "github_repo_recap",
           action: "create_draft",
           action_config: {
             "repo_name" => "forem/forem",
             "days_ago" => "7",
             "tags" => "opensource, github"
           },
           frequency: "daily",
           frequency_config: { "hour" => 9, "minute" => 0 })
  end

  let(:mock_recap_result) do
    double("RecapResult", title: "Test Recap", body: "Test content", "body=": true)
  end
  let(:mock_service) { double("GithubRepoRecap", generate: mock_recap_result) }
  let(:mock_github_client) { double("GithubClient") }

  before do
    # Set up default mocking for all tests
    allow(Github::OauthClient).to receive(:new).and_return(mock_github_client)
    allow(Ai::GithubRepoRecap).to receive(:new).and_return(mock_service)
    allow(mock_recap_result).to receive(:body=)
  end

  describe ".call" do
    it "executes the automation" do
      result = described_class.call(automation)
      expect(result).to be_a(described_class::Result)
    end
  end

  describe "#call" do
    subject(:executor) { described_class.new(automation) }

    context "when automation is already running" do
      before { automation.update!(state: "running") }

      it "returns a failure result" do
        result = executor.call
        expect(result.success?).to be(false)
        expect(result.error_message).to eq("Automation is already running")
        expect(result.article).to be_nil
      end
    end

    context "when automation executes successfully" do
      it "marks automation as running" do
        expect(automation.state).to eq("active")
        executor.call
        expect(automation.reload.state).to eq("active") # Should be back to active after completion
      end

      it "calls the AI service" do
        expect(Ai::GithubRepoRecap).to receive(:new).with(
          "forem/forem",
          days_ago: 7,
          github_client: mock_github_client
        ).and_return(mock_service)

        executor.call
      end

      it "creates an article" do
        expect { executor.call }.to change(Article, :count).by(1)
      end

      it "creates a draft article when action is create_draft" do
        result = executor.call
        expect(result.success?).to be(true)
        expect(result.article).to be_a(Article)
        expect(result.article.published).to be(false)
        expect(result.article.title).to eq("Test Recap")
        expect(result.article.body_markdown).to eq("Test content")
      end

      it "applies tags from action_config" do
        result = executor.call
        expect(result.article.tag_list).to eq(["opensource", "github"])
      end

      it "sets the next run time" do
        expect { executor.call }.to change { automation.reload.next_run_at }
      end

      it "updates last_run_at" do
        expect { executor.call }.to change { automation.reload.last_run_at }.from(nil)
      end

      it "returns success result" do
        result = executor.call
        expect(result.success?).to be(true)
        expect(result.article).to be_present
        expect(result.error_message).to be_nil
      end

      context "when action is publish_article" do
        before { automation.update!(action: "publish_article") }

        it "creates a published article" do
          result = executor.call
          expect(result.success?).to be(true)
          expect(result.article.published).to be(true)
          expect(result.article.published_at).to be_present
        end
      end

      context "when service returns nil" do
        before { allow(mock_service).to receive(:generate).and_return(nil) }

        it "returns success with no article" do
          result = executor.call
          expect(result.success?).to be(true)
          expect(result.article).to be_nil
          expect(result.error_message).to eq("No content generated (service returned nil)")
        end

        it "does not create an article" do
          expect { executor.call }.not_to change(Article, :count)
        end

        it "still updates next_run_at" do
          expect { executor.call }.to change { automation.reload.next_run_at }
        end
      end

      context "with additional instructions" do
        before do
          automation.update!(additional_instructions: "Focus on major features")
          # Allow the mock to properly handle body= setter
          allow(mock_recap_result).to receive(:body=) do |new_body|
            allow(mock_recap_result).to receive(:body).and_return(new_body)
          end
        end

        it "augments the content with instructions" do
          result = executor.call
          expect(result.article.body_markdown).to include("Test content")
          expect(result.article.body_markdown).to include("**Additional Context:**")
          expect(result.article.body_markdown).to include("Focus on major features")
        end
      end

      context "with string values in action_config" do
        before do
          automation.update!(
            action_config: {
              "repo_name" => "forem/forem",
              "days_ago" => "14", # String instead of integer
              "tags" => "test"
            }
          )
        end

        it "converts string days_ago to integer" do
          expect(Ai::GithubRepoRecap).to receive(:new).with(
            "forem/forem",
            days_ago: 14, # Should be converted to integer
            github_client: mock_github_client
          ).and_return(mock_service)

          executor.call
        end
      end

      context "with organization_id in action_config" do
        let(:organization) { create(:organization) }

        before do
          automation.action_config["organization_id"] = organization.id.to_s
          automation.save!
        end

        it "sets the article organization" do
          result = executor.call
          expect(result.article.organization_id).to eq(organization.id)
        end
      end

      context "with series in action_config" do
        before do
          automation.action_config["series"] = "daily-current-affairs-quiz"
          automation.save!
        end

        it "sets the article series collection" do
          result = executor.call

          expect(result.article.collection).to be_present
          expect(result.article.series).to eq("daily-current-affairs-quiz")
        end
      end
    end

    context "when an error occurs" do
      before do
        allow(Github::OauthClient).to receive(:new).and_raise(StandardError, "API Error")
      end

      it "marks automation as failed" do
        executor.call
        expect(automation.reload.state).to eq("failed")
      end
      it "creates an audit log entry" do
        expect { executor.call }.to change(AuditLog, :count).by(1)

        log = AuditLog.last
        expect(log.slug).to eq("scheduled_automation_failed")
        expect(log.data["automation_id"]).to eq(automation.id)
      end


      it "returns failure result" do
        result = executor.call
        expect(result.success?).to be(false)
        expect(result.article).to be_nil
        expect(result.error_message).to include("StandardError: API Error")
      end

      it "logs the error" do
        allow(Rails.logger).to receive(:error)
        executor.call
        expect(Rails.logger).to have_received(:error).at_least(:once)
      end

      it "does not create an article" do
        expect { executor.call }.not_to change(Article, :count)
      end
    end


    context "when service_name is community_bot_post_creator" do
      let(:mock_post_result) do
        double("PostResult", title: "Community Update", body: "Generated post body", tags: ["news", "current-affairs"])
      end
      let(:mock_post_service) { double("CommunityBotQuizPostCreator", generate: mock_post_result) }

      before do
        automation.update!(
          service_name: "community_bot_post_creator",
          action_config: { "ai_context" => "Write a post for our community about testing best practices" },
        )
        allow(Ai::CommunityBotQuizPostCreator).to receive(:new).and_return(mock_post_service)
      end

      it "calls the community bot post creator service" do
        expect(Ai::CommunityBotQuizPostCreator).to receive(:new).with(
          ai_context: "Write a post for our community about testing best practices",
          additional_instructions: automation.additional_instructions,
          tags: automation.action_config["tags"],
          affected_user: bot,
        ).and_return(mock_post_service)

        executor.call
      end

      it "creates an article from the generated result" do
        result = executor.call

        expect(result.success?).to be(true)
        expect(result.article.title).to eq("Community Update")
        expect(result.article.body_markdown).to eq("Generated post body")
      end

      it "treats a struct-like service result as a single article payload" do
        struct_result = Struct.new(:title, :body, :tags, :cover_image).new(
          "Structured Community Update",
          "Structured body",
          ["news"],
          nil,
        )
        allow(mock_post_service).to receive(:generate).and_return(struct_result)

        result = executor.call

        expect(result.success?).to be(true)
        expect(result.article.title).to eq("Structured Community Update")
      end

      it "applies generated tags when action_config tags are missing" do
        result = executor.call

        expect(result.article.tag_list).to eq(["news", "currentaffairs"])
      end

      it "prefers configured tags over generated tags" do
        automation.update!(
          action_config: {
            "ai_context" => "Write a post for our community about testing best practices",
            "tags" => "configured, editorial"
          },
        )

        result = executor.call

        expect(result.article.tag_list).to eq(["configured", "editorial"])
      end
    end

    context "when service_name is community_bot_current_affairs_news_post_creator" do
      let(:mock_news_post_result) do
        double("PostResult", title: "Current Affairs Update", body: "Yesterday headlines", tags: ["current-affairs", "india"])
      end
      let(:mock_news_post_service) { double("CommunityBotCurrentAffairsNewsPostCreator", generate: mock_news_post_result) }

      before do
        automation.update!(
          service_name: "community_bot_current_affairs_news_post_creator",
          action_config: { "ai_context" => "Summarize important current affairs from yesterday" },
        )
        allow(Ai::CommunityBotCurrentAffairsNewsPostCreator).to receive(:new).and_return(mock_news_post_service)
      end

      it "calls the current affairs news post creator service" do
        expect(Ai::CommunityBotCurrentAffairsNewsPostCreator).to receive(:new).with(
          ai_context: "Summarize important current affairs from yesterday",
          additional_instructions: automation.additional_instructions,
          tags: automation.action_config["tags"],
          affected_user: bot,
        ).and_return(mock_news_post_service)

        executor.call
      end

      it "creates an article from the generated result" do
        result = executor.call

        expect(result.success?).to be(true)
        expect(result.article.title).to eq("Current Affairs Update")
        expect(result.article.body_markdown).to eq("Yesterday headlines")
      end
    end

    context "when service_name is community_bot_trending_article_creator" do
      let(:trend_result_one) do
        double("PostResultOne", title: "Trend One", body: "Body one", tags: ["trend-one"], cover_image: nil)
      end
      let(:trend_result_two) do
        double("PostResultTwo", title: "Trend Two", body: "Body two", tags: ["trend-two"], cover_image: nil)
      end
      let(:mock_trending_service) { double("CommunityBotTrendingArticleCreator", generate: [trend_result_one, trend_result_two]) }

      before do
        automation.update!(
          service_name: "community_bot_trending_article_creator",
          action: "create_draft",
          action_config: { "ai_context" => "Write trend updates" },
        )
        allow(Ai::CommunityBotTrendingArticleCreator).to receive(:new).and_return(mock_trending_service)
      end

      it "creates one article for each generated trend result" do
        expect { executor.call }.to change(Article, :count).by(2)
      end

      it "returns the last created article in the result payload" do
        result = executor.call

        expect(result.success?).to be(true)
        expect(result.article.title).to eq("Trend Two")
      end

      it "skips invalid generated cover images instead of failing article creation" do
        invalid_cover_image_result = double(
          "PostResultWithInvalidCoverImage",
          title: "Trend Invalid Cover",
          body: "Body invalid cover",
          tags: ["trend-invalid"],
          cover_image: "![invalid](https://example.com/image.jpg)",
        )
        allow(mock_trending_service).to receive(:generate).and_return([invalid_cover_image_result])

        result = executor.call

        expect(result.success?).to be(true)
        expect(result.article.main_image).to be_nil
      end
    end

    context "when service_name is unknown" do
      before { automation.update!(service_name: "unknown_service") }

      it "raises an ArgumentError" do
        result = executor.call
        expect(result.success?).to be(false)
        expect(result.error_message).to include("Unknown service: unknown_service")
      end
    end


    context "when ai_context is missing for community_bot_post_creator" do
      before do
        automation.update!(service_name: "community_bot_post_creator", action_config: {})
      end

      it "returns failure result" do
        result = executor.call

        expect(result.success?).to be(false)
        expect(result.error_message).to include("ai_context is required")
      end
    end

    context "when ai_context is missing for community_bot_current_affairs_news_post_creator" do
      before do
        automation.update!(service_name: "community_bot_current_affairs_news_post_creator", action_config: {})
      end

      it "returns failure result" do
        result = executor.call

        expect(result.success?).to be(false)
        expect(result.error_message).to include("ai_context is required")
      end
    end

    context "when action is invalid" do
      # Skip this test since action validation is handled at the model level
      # The executor assumes it receives a valid automation object
    end

    context "when repo_name is missing" do
      before do
        automation.update!(action_config: { "days_ago" => 7 })
      end

      it "returns failure result" do
        result = executor.call
        expect(result.success?).to be(false)
        expect(result.error_message).to include("repo_name is required")
      end
    end

    context "when action is award_first_org_post_badge" do
      let(:organization) { create(:organization) }
      let(:badge) { create(:badge, slug: "first-org-post", title: "First Org Post") }
      let(:badge_automation) do
        create(:scheduled_automation,
               user: bot,
               service_name: "first_org_post_badge",
               action: "award_first_org_post_badge",
               action_config: {
                 "organization_id" => organization.id,
                 "badge_slug" => badge.slug
               },
               frequency: "daily",
               frequency_config: { "hour" => 9, "minute" => 0 })
      end
      let(:badge_executor) { described_class.new(badge_automation) }

      it "calls FirstPostBadgeAwarder service" do
        expect(ScheduledAutomations::FirstPostBadgeAwarder).to receive(:call).with(badge_automation).and_return(
          ScheduledAutomations::FirstPostBadgeAwarder::Result.new(
            success?: true,
            users_awarded: 2,
            error_message: nil
          )
        )

        result = badge_executor.call
        expect(result.success?).to be(true)
      end

      it "does not call AI service for badge awarding action" do
        expect(Ai::GithubRepoRecap).not_to receive(:new)
        badge_executor.call
      end

      it "marks automation as completed after badge awarding" do
        allow(ScheduledAutomations::FirstPostBadgeAwarder).to receive(:call).and_return(
          ScheduledAutomations::FirstPostBadgeAwarder::Result.new(
            success?: true,
            users_awarded: 1,
            error_message: nil
          )
        )

        expect { badge_executor.call }.to change { badge_automation.reload.last_run_at }.from(nil)
        expect(badge_automation.reload.state).to eq("active")
      end

      it "handles badge awarding failures" do
        allow(ScheduledAutomations::FirstPostBadgeAwarder).to receive(:call).and_return(
          ScheduledAutomations::FirstPostBadgeAwarder::Result.new(
            success?: false,
            users_awarded: 0,
            error_message: "Badge not found"
          )
        )

        result = badge_executor.call
        expect(result.success?).to be(false)
        expect(result.error_message).to eq("Badge not found")
      end

      context "with actual badge awarding" do
        let(:user) { create(:user) }

        it "awards badges to eligible users" do
          create(:article, :past,
                 user: user,
                 organization: organization,
                 published: true,
                 past_published_at: 1.day.ago)

          result = badge_executor.call

          expect(result.success?).to be(true)
          expect(user.badge_achievements.where(badge: badge).count).to eq(1)
        end
      end
    end
  end
end
