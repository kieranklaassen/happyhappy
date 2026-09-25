class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps

      t.index :name, unique: true
      t.index :token_digest, unique: true
    end
  end
end
