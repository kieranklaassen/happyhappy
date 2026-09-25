class AddAuthorRoleToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :author_role, :string, default: "unknown", null: false
    add_column :messages, :classifier_version, :string
    add_index :messages, [ :item_id, :author_role ]

    add_column :settings, :team_email_domains, :json, default: [ "every.to" ], null: false
    add_column :settings, :team_discord_role_ids, :json, default: [], null: false
    add_column :settings, :team_discord_user_ids, :json, default: [], null: false
  end
end
