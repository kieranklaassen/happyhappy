class AddExternalStateToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :external_state, :string
  end
end
