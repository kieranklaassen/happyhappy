class AddUserToAgents < ActiveRecord::Migration[8.1]
  def change
    add_reference :agents, :user, foreign_key: true, index: { unique: true }
  end
end
