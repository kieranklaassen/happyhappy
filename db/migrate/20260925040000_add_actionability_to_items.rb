class AddActionabilityToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :actionability, :float
    add_column :items, :actionability_band, :string
    add_index :items, [ :actionability_band, :actionability ]
  end
end
