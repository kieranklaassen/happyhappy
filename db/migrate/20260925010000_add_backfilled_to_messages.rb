class AddBackfilledToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :backfilled, :boolean, default: false, null: false
  end
end
