# frozen_string_literal: true

module PushNotifications
  class PayloadFactory
    def self.build(notification)
      new(notification).build
    end

    def initialize(notification)
      @notification = notification
    end

    def build
      builder = resolve_builder
      return nil unless builder

      builder.build
    end

    private

    attr_reader :notification

    def resolve_builder
      case notification.notifiable_type
      when "Comment"
        resolve_comment_builder
      when "Mention"
        Payload::MentionPayload.new(notification.notifiable)
      when "Article"
        resolve_article_builder
      when "BadgeAchievement"
        Payload::BadgePayload.new(badge_achievement: notification.notifiable)
      when "Follow"
        resolve_follow_builder
      else
        nil
      end
    rescue StandardError => e
      Rails.logger.error("[PayloadFactory] Error building payload for Notification##{notification.id}: #{e.message}")
      nil
    end

    def resolve_comment_builder
      comment = notification.notifiable
      return nil unless comment

      notification_type = if comment.parent_id.present?
                            :comment_reply
                          else
                            :comment_article
                          end

      Payload::CommentPayload.new(comment: comment, notification_type: notification_type)
    end

    def resolve_article_builder
      article = notification.notifiable
      return nil unless article

      if notification.action&.include?("Milestone")
        type = notification.action.split("::").last&.downcase || "view"
        count = notification.json_data&.dig("milestone", "count") || 0
        Payload::MilestonePayload.new(
          article: article,
          milestone_type: type.capitalize,
          milestone_count: count
        )
      end
    end

    def resolve_follow_builder
      follower = User.find_by(id: notification.json_data&.dig("user", "id"))
      followable = User.find_by(id: notification.user_id)
      return nil unless follower && followable

      Payload::FollowerPayload.new(follower: follower, followable: followable)
    end
  end
end
