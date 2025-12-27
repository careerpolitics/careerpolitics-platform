# frozen_string_literal: true

module PushNotifications
  module Payload
    class FollowerPayload < BasePayload
      attr_reader :follower, :followable

      def initialize(follower:, followable:)
        super(:new_follower)
        follower = follower
        followable = followable
      end

      def build
        base_payload(
          title: build_title,
          body: build_body,
          target: build_follower_target,
          actor: build_actor(follower),
          action_context: build_action_context
        )
      end

      private

      # -------------------------
      # Title
      # -------------------------
      def build_title
        I18n.t("services.notifications.push_notifications.follower.title")
      end

      def build_body
        if followable.is_a?(Organization)
          I18n.t("services.notifications.push_notifications.follower.organization_body",
                 username: follower.username,
                 organization: followable.name)
        else
          I18n.t("services.notifications.push_notifications.follower.user_body",
                 username: follower.username)
        end
      end

      # -------------------------
      # Target
      # -------------------------
      def build_follower_target
        build_target(
          type: followable.class.name,
          id: followable.id,
          title: followable.respond_to?(:name) ? followable.name : followable.username,
          url: build_url(followable.path)
        )
      end

      # -------------------------
      # Action Context
      # -------------------------
      def build_action_context
        {
          follower_id: follower.id,
          follower_username: follower.username,
          followable_type: followable.class.name,
          followable_id: followable.id,
        }
      end
    end
  end
end
