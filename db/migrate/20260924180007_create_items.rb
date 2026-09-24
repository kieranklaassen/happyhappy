class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.references :source, null: false, foreign_key: true
      t.string :source_kind, null: false
      t.string :thread_key, null: false
      t.string :author_handle
      t.string :author_name
      t.string :author_email
      t.string :permalink
      t.string :status, null: false, default: "new"
      t.datetime :status_changed_at, null: false

      t.references :product, foreign_key: true
      t.references :category, foreign_key: true
      t.string :sentiment
      t.float :product_probability
      t.float :category_probability
      t.float :sentiment_probability
      t.float :relevance_probability
      t.float :anger_probability
      t.boolean :relevant, null: false, default: true
      t.boolean :needs_review, null: false, default: false
      t.boolean :product_human_set, null: false, default: false
      t.boolean :category_human_set, null: false, default: false
      t.boolean :sentiment_human_set, null: false, default: false
      t.boolean :relevant_human_set, null: false, default: false

      t.references :claimed_by_agent, foreign_key: { to_table: :agents }
      t.datetime :claimed_at
      t.datetime :last_reported_at
      t.boolean :overdue, null: false, default: false
      t.datetime :last_message_at, null: false
      t.timestamps

      t.index [ :source_kind, :thread_key ], unique: true
      t.index :status
      t.index :sentiment
      t.index :last_message_at
    end
  end
end
