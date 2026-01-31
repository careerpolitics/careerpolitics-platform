# frozen_string_literal: true

module PushNotifications
  module Payload
    class BadgePayload < BasePayload
      attr_reader :badge_achievement

      def initialize(badge_achievement:)
        super(:badge_earned)
        @badge_achievement = badge_achievement
      end

      def build
        base_payload(
          title: build_title,
          body: build_body,
          target: build_badge_target,
          actor: build_actor(badge_achievement.user),
          action_context: build_action_context
        )
      end

      private

      # -------------------------
      # Title
      # -------------------------
      def build_title
        I18n.t("services.notifications.push_notifications.badge.title")
      end

      # -------------------------
      # Body
      # -------------------------
      def build_body
        I18n.t("services.notifications.push_notifications.badge.body",
          badge: badge_achievement.badge.title)
      end

      # -------------------------
      # Target
      # -------------------------
      def build_badge_target
        build_target(
          type: "BadgeAchievement",
          id: badge_achievement.id,
          title: badge_achievement.badge.title,
          url: build_url("/badge/#{badge_achievement.badge.slug}"),
        )
      end

      # -------------------------
      # Action Context
      # -------------------------
      def build_action_context
        {
          badge_id: badge_achievement.badge_id,
          badge_title: badge_achievement.badge.title,
          badge_description: badge_achievement.badge.description,
          badge_image_url: badge_achievement.badge.badge_image_url,
          credits_awarded: badge_achievement.badge.credits_awarded,
          rewarding_context_message: badge_achievement.rewarding_context_message,
          badge_achievement_id: badge_achievement.id
        }
      end
    end
  end
end
