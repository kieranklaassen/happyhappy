class CreateWebhookEndpointsAndDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.text :secret, null: false
      t.json :events, null: false, default: []
      t.json :product_ids, null: false, default: []
      t.json :category_ids, null: false, default: []
      t.json :sentiments, null: false, default: []
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :webhook_deliveries do |t|
      t.references :webhook_endpoint, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :item_event, foreign_key: { on_delete: :nullify }
      t.string :event, null: false
      t.json :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :response_code
      t.text :last_error
      t.datetime :last_attempted_at
      t.boolean :test, null: false, default: false
      t.timestamps

      t.index [ :webhook_endpoint_id, :created_at ]
      t.index :created_at
    end
  end
end
