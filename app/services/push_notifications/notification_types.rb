module PushNotifications
  class NotificationTypes
    # -------------------------
    # Notification Categories
    # -------------------------
    CATEGORY_COMMENT     = "comment"
    CATEGORY_MENTION     = "mention"
    CATEGORY_REACTION    = "reaction"
    CATEGORY_SOCIAL      = "social"
    CATEGORY_ACHIEVEMENT = "achievement"
    CATEGORY_MILESTONE   = "milestone"
    CATEGORY_MODERATION  = "moderation"
    CATEGORY_GENERAL     = "general"

    # -------------------------
    # Notification Priorities
    # -------------------------
    PRIORITY_HIGH    = "high"
    PRIORITY_DEFAULT = "default"
    PRIORITY_LOW     = "low"

    # -------------------------
    # Android Notification Channels
    # -------------------------
    CHANNEL_COMMENT_REPLIES   = "comment_replies"
    CHANNEL_COMMENT_THREADS  = "comment_threads"
    CHANNEL_MENTIONS         = "mentions"
    CHANNEL_REACTIONS        = "reactions"
    CHANNEL_FOLLOWERS        = "followers"
    CHANNEL_BADGES           = "badges"
    CHANNEL_MILESTONES       = "milestones"
    CHANNEL_MODERATION       = "moderation"
    CHANNEL_GENERAL          = "general"

    # -------------------------
    # Standard UI Colors
    # -------------------------
    COLOR_PRIMARY   = "#3b49df"
    COLOR_SOCIAL    = "#2f855a"
    COLOR_REACTION  = "#805ad5"
    COLOR_MENTION   = "#d53f8c"
    COLOR_BADGE     = "#d69e2e"
    COLOR_MILESTONE = "#3182ce"
    COLOR_ALERT     = "#c53030"
    COLOR_NEUTRAL   = "#4a5568"

    # -------------------------
    # Notification Type Definitions
    # -------------------------
    TYPES = {
      comment_reply: {
        category:  CATEGORY_COMMENT,
        priority:  PRIORITY_HIGH,
        channel:   CHANNEL_COMMENT_REPLIES,
        icon:      "comment",
        color:     COLOR_PRIMARY,
        groupable: true,
        actions:   %i[reply like view mark_read]
      },

      comment_thread: {
        category:  CATEGORY_COMMENT,
        priority:  PRIORITY_DEFAULT,
        channel:   CHANNEL_COMMENT_THREADS,
        icon:      "comment",
        color:     COLOR_PRIMARY,
        groupable: true,
        actions:   %i[view mark_read]
      },

      mention: {
        category:  CATEGORY_MENTION,
        priority:  PRIORITY_HIGH,
        channel:   CHANNEL_MENTIONS,
        icon:      "mention",
        color:     COLOR_MENTION,
        groupable: true,
        actions:   %i[reply view mark_read]
      },

      reaction_single: {
        category:  CATEGORY_REACTION,
        priority:  PRIORITY_DEFAULT,
        channel:   CHANNEL_REACTIONS,
        icon:      "reaction",
        color:     COLOR_REACTION,
        groupable: false,
        actions:   %i[view mark_read]
      },

      reaction_multiple: {
        category:  CATEGORY_REACTION,
        priority:  PRIORITY_DEFAULT,
        channel:   CHANNEL_REACTIONS,
        icon:      "reaction",
        color:     COLOR_REACTION,
        groupable: true,
        actions:   %i[view mark_read]
      },

      new_follower: {
        category:  CATEGORY_SOCIAL,
        priority:  PRIORITY_DEFAULT,
        channel:   CHANNEL_FOLLOWERS,
        icon:      "user",
        color:     COLOR_SOCIAL,
        groupable: true,
        actions:   %i[view mark_read]
      },

      badge_earned: {
        category:  CATEGORY_ACHIEVEMENT,
        priority:  PRIORITY_DEFAULT,
        channel:   CHANNEL_BADGES,
        icon:      "badge",
        color:     COLOR_BADGE,
        groupable: false,
        actions:   %i[view mark_read]
      },

      milestone_reached: {
        category:  CATEGORY_MILESTONE,
        priority:  PRIORITY_DEFAULT,
        channel:   CHANNEL_MILESTONES,
        icon:      "milestone",
        color:     COLOR_MILESTONE,
        groupable: false,
        actions:   %i[view mark_read]
      },

      moderation: {
        category:  CATEGORY_MODERATION,
        priority:  PRIORITY_HIGH,
        channel:   CHANNEL_MODERATION,
        icon:      "shield",
        color:     COLOR_ALERT,
        groupable: false,
        actions:   %i[view mark_read]
      },

      general: {
        category:  CATEGORY_GENERAL,
        priority:  PRIORITY_DEFAULT,
        channel:   CHANNEL_GENERAL,
        icon:      "info",
        color:     COLOR_NEUTRAL,
        groupable: true,
        actions:   %i[view mark_read]
      }
    }.freeze

    # -------------------------
    # Class Helpers
    # -------------------------
    class << self
      # Get configuration for a notification type
      def config(type)
        TYPES[type.to_sym] || TYPES[:comment_reply]
      end

      # Get priority for a notification type
      def priority(type)
        config(type)[:priority]
      end

      # Get category for a notification type
      def category(type)
        config(type)[:category]
      end

      # Get channel for a notification type
      def channel(type)
        config(type)[:channel]
      end

      # Get icon for a notification type
      def icon(type)
        config(type)[:icon]
      end

      # Get color for a notification type
      def color(type)
        config(type)[:color]
      end

      # Check if notification supports grouping
      def groupable?(type)
        config(type)[:groupable]
      end

      # Get available actions for a notification type
      def actions(type)
        config(type)[:actions]
      end

      # Get all available notification types
      def all_types
        TYPES.keys
      end
    end
  end
end
