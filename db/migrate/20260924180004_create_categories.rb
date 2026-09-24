class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.datetime :retired_at
      t.timestamps

      t.index :name, unique: true
    end
  end
end
