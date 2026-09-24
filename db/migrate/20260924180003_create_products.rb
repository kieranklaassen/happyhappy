class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.json :hint_words, null: false, default: []
      t.string :slack_channel_id
      t.float :escalation_threshold
      t.integer :digest_hour, null: false, default: 9
      t.datetime :retired_at
      t.timestamps

      t.index :name, unique: true
      t.index :slug, unique: true
    end
  end
end
