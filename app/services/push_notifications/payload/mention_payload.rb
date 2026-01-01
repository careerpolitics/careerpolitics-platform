# frozen_string_literal: true

module PushNotifications
  module Payload
    class MentionPayload < BasePayload
      attr_reader :mention

      def initialize(mention)
        super(:mention)
        @mention = mention
      end

      def build
        base_payload(
          title: build_title,
          body: build_body,
          target: build_mention_target,
          actor: build_actor(mention.mentionable.user),
          action_context: build_action_context
        )
      end

      private

      def build_title
        I18n.t("services.notifications.push_notifications.mention.title", username: mention.mentionable.user.username)
      end

      def build_body
        mentionable = mention.mentionable

        text = strip_tags(mentionable.processed_html).strip

        if mentionable.is_a?(Article)
          I18n.t(
            "services.notifications.push_notifications.mention.article_body",
            article: mentionable.title.strip,
            text: text.truncate(100)
          )
        else
          article_title = mentionable.commentable.title.strip

          I18n.t(
            "services.notifications.push_notifications.mention.comment_body",
            article: article_title,
            text: text.truncate(100)
          )
        end
      end


      def build_mention_target
        mentionable = mention.mentionable

        if mentionable.is_a?(Article)
          build_target(
            type: "Article",
            id: mentionable.id,
            title: mentionable.title,
            url: build_url(mentionable.path)
          )
        else
          # Comment mention (default)
          build_target(
            type: "Comment",
            id: mentionable.id,
            title: mentionable.commentable.title,
            url: build_url(mentionable.path)
          )
        end
      end


      def build_action_context
        mentionable = mention.mentionable

        if mentionable.is_a?(Article)
          {
            mention_id: mention.id,
            mentionable_type: "Article",
            article_id: mentionable.id,
            article_title: mentionable.title,
            comment_id: nil
          }
        else
          # Comment mention (default)
          {
            mention_id: mention.id,
            mentionable_type: "Comment",
            article_id: mentionable.commentable_id,
            article_title: mentionable.commentable.title,
            comment_id: mentionable.id
          }
        end
      end
    end
  end
end
