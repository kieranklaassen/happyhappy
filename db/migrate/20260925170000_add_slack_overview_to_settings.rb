class AddSlackOverviewToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :slack_channel_id, :string
    add_column :settings, :digest_time_zone, :string, default: "America/Los_Angeles", null: false
    add_column :settings, :digest_hour, :integer, default: 8, null: false
  end
end
