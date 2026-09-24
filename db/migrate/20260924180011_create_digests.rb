class CreateDigests < ActiveRecord::Migration[8.1]
  def change
    create_table :digests do |t|
      t.references :product, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.string :slack_message_ts
      t.datetime :posted_at
      t.text :last_error
      t.timestamps

      t.index [ :product_id, :date ], unique: true
    end
  end
end
