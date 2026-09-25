class CreateOverviewDigests < ActiveRecord::Migration[8.1]
  def change
    create_table :overview_digests do |t|
      t.date :date, null: false
      t.datetime :posted_at
      t.string :slack_message_ts
      t.text :last_error
      t.timestamps
    end
    add_index :overview_digests, :date, unique: true
  end
end
