class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :kind, null: false
      t.string :name, null: false
      t.references :default_product, foreign_key: { to_table: :products }
      t.string :selector, null: false
      t.string :status, null: false, default: "active"
      t.datetime :last_message_at
      t.text :last_error
      t.datetime :last_error_at
      t.decimal :monthly_limit, precision: 10, scale: 4
      t.decimal :month_spend, precision: 10, scale: 4, null: false, default: 0
      t.string :month_key
      t.string :since_id
      t.timestamps

      t.index [ :kind, :selector ], unique: true
    end
  end
end
