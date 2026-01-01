# frozen_string_literal: true

module PushNotifications
  module Payload
    class MilestonePayload < BasePayload
      attr_reader :article, :milestone_type, :milestone_count

      def initialize(article:, milestone_type:, milestone_count:)
        super(:milestone_reached)
        @article = article
        @milestone_type = milestone_type
        @milestone_count = milestone_count
      end

      def build
        base_payload(
          title: build_title,
          body: build_body,
          target: build_milestone_target,
          actor: build_actor(article.user),
          action_context: build_action_context
        )
      end

      private

      # -------------------------
      # Title
      # -------------------------
      def build_title
        I18n.t("services.notifications.push_notifications.milestone.title")
      end

      # -------------------------
      # Body
      # -------------------------
      def build_body
        case milestone_type
        when "View"
          I18n.t(
            "services.notifications.push_notifications.milestone.views_body",
            title: article.title,
            count: milestone_count
          )

        when "Reaction"
          I18n.t(
            "services.notifications.push_notifications.milestone.reactions_body",
            title: article.title,
            count: milestone_count
          )

        else
          # Fallback for unknown or future milestone types
          I18n.t(
            "services.notifications.push_notifications.generic.body",
            title: article.title,
            count: milestone_count,
            type: milestone_type.downcase
          )
        end
      end


      # -------------------------
      # Target
      # -------------------------
      def build_milestone_target
        build_target(
          type: "Article",
          id: article.id,
          title: article.title,
          url: build_url(article.path)
        )
      end

      # -------------------------
      # Action Context
      # -------------------------
      def build_action_context
        {
          article_id: article.id,
          article_title: article.title,
          milestone_type: milestone_type,
          milestone_count: milestone_count,
          current_views: article.page_views_count,
          current_reactions: article.public_reactions_count,
        }
      end
    end
  end
end
