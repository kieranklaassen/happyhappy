class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :item, null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :body, null: false, default: ""
      t.datetime :occurred_at, null: false
      t.json :raw_payload, null: false, default: {}
      t.json :classification_answers
      t.float :anger_probability
      t.datetime :classified_at
      t.text :classification_error
      t.timestamps

      t.index [ :source_id, :external_id ], unique: true
      t.index [ :item_id, :created_at ]
    end
  end
end
