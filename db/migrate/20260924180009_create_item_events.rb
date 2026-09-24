class CreateItemEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :item_events do |t|
      t.references :item, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.references :actor, polymorphic: true
      t.json :data, null: false, default: {}
      t.datetime :created_at, null: false

      t.index [ :item_id, :created_at ]
      t.index :kind
    end
  end
end
