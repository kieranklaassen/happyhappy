class CreateEscalations < ActiveRecord::Migration[8.1]
  def change
    create_table :escalations do |t|
      t.references :item, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :message, foreign_key: true
      t.string :slack_channel_id, null: false
      t.string :slack_message_ts
      t.datetime :posted_at
      t.text :last_error
      t.timestamps
    end
  end
end
