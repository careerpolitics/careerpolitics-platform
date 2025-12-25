# frozen_string_literal: true

class AddMobileNotificationSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :users_notification_settings, :mobile_reaction_notifications, :boolean, default: true, null: false
    add_column :users_notification_settings, :mobile_follower_notifications, :boolean, default: true, null: false
    add_column :users_notification_settings, :mobile_badge_notifications, :boolean, default: true, null: false
    add_column :users_notification_settings, :mobile_milestone_notifications, :boolean, default: true, null: false
  end
end
