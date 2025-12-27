# frozen_string_literal: true

module PushNotifications
  module Payload
    class BasePayload
      include ActionView::Helpers::TextHelper
      include ActionView::Helpers::SanitizeHelper

      attr_reader :notification_type

      def initialize(notification_type)
        @notification_type = notification_type.to_sym
      end

      def build
        raise NotImplementedError, "Subclasses must implement #build"
      end

      protected

      def config
        @config ||= PushNotifications::NotificationTypes.config(notification_type)
      end

      def base_payload(title:, body:, target:, actor: nil, action_context: {})
        {
          notification_type: notification_type.to_s,
          category: config[:category],
          priority: config[:priority],
          title: title,
          body: truncate_body(body),
          channel: config[:channel],
          icon: config[:icon],
          color: config[:color],
          timestamp: Time.current.to_i,
          url: target&.dig(:url)
        }.tap do |payload|
          payload[:actor] = actor if actor.present?
          payload[:target] = target if target.present?
          payload[:action_context] = action_context if action_context.present?

          if config[:groupable] && target.present?
            payload[:group_key] = generate_group_key(target)
          end

          payload[:actions] = build_actions if config[:actions].present?
        end
      end

      def build_actor(user)
        return nil unless user

        {
          id: user.id,
          username: user.username,
          name: user.name,
          avatar_url: user.profile_image_90
        }
      end

      def build_target(type:, id:, title:, url:)
        {
          type: type,
          id: id,
          title: title,
          url: url
        }
      end

      def truncate_body(body, length: 200)
        strip_tags(body.to_s).strip.truncate(length)
      end

      def generate_group_key(target)
        return nil unless target.is_a?(Hash)

        case target[:type]
        when "Article"
          "article_#{target[:id]}"
        when "Comment"
          "comment_#{target[:id]}"
        else
          "general_#{target[:id]}"
        end
      end

      def build_actions
        config[:actions].map do |action_id|
          build_action(action_id)
        end.compact
      end

      def build_action(action_id)
        case action_id
        when :reply
          { id: "reply", label: "Reply", type: "text_input", icon: "reply" }
        when :like
          { id: "like", label: "Like", type: "button", icon: "heart" }
        when :view
          { id: "view", label: "View", type: "navigation", icon: "open" }
        when :mark_read
          { id: "mark_read", label: "Mark as read", type: "button", icon: "check" }
        when :follow_back
          { id: "follow_back", label: "Follow back", type: "button", icon: "person_add" }
        when :view_profile
          { id: "view_profile", label: "View profile", type: "navigation", icon: "person" }
        when :view_badges
          { id: "view_badges", label: "View badges", type: "navigation", icon: "badge" }
        when :view_stats
          { id: "view_stats", label: "View stats", type: "navigation", icon: "chart" }
        end
      end

      def build_url(path)
        URL.url(path)
      end
    end
  end
end
