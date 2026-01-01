# frozen_string_literal: true

module PushNotifications
  module Payload
    class CommentPayload < BasePayload
      attr_reader :comment

      def initialize(comment:, notification_type:)
        super(notification_type)
        @comment = comment
      end

      def build
        base_payload(
          title: build_title,
          body: build_body,
          target: build_comment_target,
          actor: build_actor(comment.user),
          action_context: build_action_context
        )
      end

      private

      def build_title
        case notification_type
        when :comment_reply
          I18n.t(
            "services.notifications.push_notifications.comment.reply_title",
            username: comment.user.username
          )
        when :comment_article
          I18n.t(
            "services.notifications.push_notifications.comment.article_title",
            username: comment.user.username
          )
        when :comment_thread
          I18n.t("services.notifications.push_notifications.comment.thread_title")
        else
          I18n.t("services.notifications.new_comment.new")
        end
      end

      def build_body
        article_title = comment.commentable.title.strip
        comment_text  = strip_tags(comment.processed_html).strip

        case notification_type
        when :comment_reply
          comment_text

        when :comment_article
          I18n.t(
            "services.notifications.push_notifications.comment.article_body",
            article: article_title,
            comment: comment_text.truncate(100)
          )

        when :comment_thread
          I18n.t(
            "services.notifications.push_notifications.comment.thread_body",
            article: article_title,
            comment: comment_text.truncate(100)
          )

        else
          "#{I18n.t(
            'views.notifications.comment.commented_html',
            user: comment.user.username,
            title: article_title
          )}:\n#{comment_text}"
        end
      end

      def build_comment_target
        build_target(
          type: "Comment",
          id: comment.id,
          title: comment.commentable.title,
          url: build_url(comment.path)
        )
      end

      def build_action_context
        {
          comment_id: comment.id,
          article_id: comment.commentable.id,
          article_title: comment.commentable.title,
          parent_comment_id: comment.parent_id,
          thread_depth: comment.depth,
          commentable_type: comment.commentable_type,
          subforem_id: comment.commentable.subforem_id
        }
      end
    end
  end
end
