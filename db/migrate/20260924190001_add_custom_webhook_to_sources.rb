class AddCustomWebhookToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :public_token, :string
    add_column :sources, :signing_secret, :text
    add_index :sources, :public_token, unique: true
  end
end
