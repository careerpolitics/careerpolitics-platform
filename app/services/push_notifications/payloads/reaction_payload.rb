# frozen_string_literal: true

module PushNotifications
  module Payload
    class ReactionPayload < BasePayload
      attr_reader :reaction, :aggregated_siblings

      def initialize(reaction:, aggregated_siblings:)
        notification_type= aggregated_siblings.size>1? :reaction_multiple: :reaction_single
        super(notification_type)
        @reaction = reaction
        @aggregated_siblings=aggregated_siblings
      end

      def build
        base_payload(
          title: build_title,
          body: build_body,
          target: build_reaction_target,
          actor: build_actor(reaction.user),
          action_context: build_action_context
        )
      end

      private

      # -------------------------
      # Title
      # -------------------------
      def build_title
        case notification_type
        when :reaction_single
          I18n.t(
            "services.notifications.push_notifications.reaction.single_title",
            username: reaction.user.username
          )
        when :reaction_multiple
          I18n.t(
            "services.notifications.push_notifications.reaction.multiple_title",
            count: aggregated_siblings.size
          )
        end
      end

      # -------------------------
      # Body
      # -------------------------
      def build_body
        reactable= reaction.reactable
        title= reactable.title

        if notification_type==:reaction_multiple
          usernames= aggregated_siblings.first(3).map{|r| r[:user][:username]}
          emoji= emoji_for_category(reaction.category)

          if aggregated_siblings.size>3
            others_count= aggregated_siblings.size-3
            I18n.t("services.notifications.push_notifications.reaction.multiple_body_with_others",
                   emoji: emoji,
                   users: usernames.join(", "),
                   count: others_count,
                   title: title)

          else
            I18n.t("services.notifications.push_notifications.reaction.multiple_body",
                   emoji: emoji,
                   users: usernames.join(", "),
                   title: title)
          end
        else
          emoji= emoji_for_category(reaction.category)
          I18n.t("services.notifications.push_notifications.reaction.single_body",
                 emoji: emoji,
                 users: usernames.join(", "),
                 title: title)
        end
      end

      # -------------------------
      # Target
      # -------------------------
      def build_reaction_target
        reactable= reaction.reactable
          # Comment reaction
          build_target(
            type: reactable.class.name,
            id: reactable.id,
            title: reactable.title,
            url: build_url(reactable.path)
          )
      end

      # -------------------------
      # Action Context
      # -------------------------
      def build_action_context
          {
            reaction_id: reaction.id,
            reactable_type: reaction.reactable_type,
            reactable_id: reaction.reactable_id,
            reaction_category: reaction.category,
            reaction_count: aggregated_siblings.size,
            reaction_types: aggregated_siblings.map{|r| r[:category]}.uniq,
            recent_reactors: aggregated_siblings.first(5).map{|r| r[:user]}
          }
      end

      def emoji_for_category(category)
        case category.to_s
        when "like", "thumbsup"
          "👍"
        when "heart", "love"
          "❤️"
        when "unicorn"
          "🦄"
        when "fire", "lit"
          "🔥"
        when "raised_hands", "hands"
          "🙌"
        when "thinking"
          "🤔"
        else
          "👍"
        end
      end

    end
  end
end
