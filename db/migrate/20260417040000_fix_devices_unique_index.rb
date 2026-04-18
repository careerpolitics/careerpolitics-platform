class FixDevicesUniqueIndex < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    remove_index :devices,
                 name: "index_devices_on_user_id_and_token_and_platform_and_app",
                 algorithm: :concurrently,
                 if_exists: true

    add_index :devices,
              %i[user_id platform consumer_app_id],
              unique: true,
              name: "index_devices_on_user_platform_and_app",
              algorithm: :concurrently
  end
end
