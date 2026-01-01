module Notifications
  module NewMention
    class Send
      include ActionView::Helpers::TextHelper

      delegate :user_data, to: Notifications
      delegate :comment_data, to: Notifications
      delegate :article_data, to: Notifications

      def self.call(...)
        new(...).call
      end

      def initialize(mention)
        @mention = mention
      end

      def call
        return if mention.mentionable.score.negative?

        Notification.create(
          user_id: mention.user_id,
          notifiable_id: mention.id,
          notifiable_type: "Mention",
          subforem_id: mention.mentionable.subforem_id,
          action: nil,
          json_data: json_data,
        )

      #   Send enhanced push notification
        send_push_notification
      end

      private

      attr_reader :mention

      def json_data
        data = { user: user_data(mention.mentionable.user) }

        case mention.mentionable_type
        when "Comment"
          data[:comment] = comment_data(mention.mentionable)
        when "Article"
          data[:article] = article_data(mention.mentionable)
        end

        data
      end

      def send_push_notification
        payload_builder = PushNotifications::Payload::MentionPayload.new(mention)

        PushNotifications::UnifiedNotifier.call(
          user_ids: [mention.user_id],
          payload_builder: payload_builder,
          preference_key: :mobile_mention_notifications,
        )
      end
    end
  end
end
