# frozen_string_literal: true

module PushNotifications
  class UnifiedNotifier

    def self.call(...)
      new(...).call
    end

    def initialize(user_ids:, payload_builder:, preference_key:)
      @user_ids = user_ids
      @payload_builder = payload_builder
      @preference_key = preference_key
    end

    def call
      return if user_ids.empty?
      filtered_user_ids = filter_users_by_preference

      return if filtered_user_ids.empty?

      rich_payload = payload_builder.build

      PushNotifications::Send.call(
        payload: rich_payload,
        user_ids: filtered_user_ids,
        body:rich_payload[:body],
        payload: rich_payload,
      )
    end

    private

    attr_reader :user_ids, :payload_builder, :preference_key

    # -------------------------
    # Preference Filtering
    # -------------------------
    def filter_users_by_preference
      return user_ids if preference_key.blank?

      User
        .joins(:notification_setting)
        .where(id: user_ids)
        .where("users_notification_settings.#{preference_key}" => true)
        .ids
    end
  end
end
