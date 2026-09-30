class CreateIncidents < ActiveRecord::Migration[8.1]
  def change
    create_table :incidents do |t|
      t.references :product, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: "open"
      t.datetime :opened_at, null: false
      t.datetime :last_anomaly_at, null: false
      t.datetime :resolved_at
      t.references :resolved_by, polymorphic: true
      t.string :resolved_by_name
      t.text :resolution_note
      t.boolean :items_handled, null: false, default: false
      t.string :slack_channel_id
      t.string :slack_message_ts
      t.timestamps
    end
    add_index :incidents, %i[product_id status last_anomaly_at]

    add_reference :anomalies, :incident
    add_column :anomalies, :resolved_at, :datetime

    add_column :products, :alert_channel_id, :string
    add_column :products, :alert_mention_ids, :json, null: false, default: []

    add_column :settings, :incident_window_minutes, :integer, null: false, default: 120
    add_column :settings, :slack_interactivity, :boolean, null: false, default: false
  end
end
