class AddEveryIdentityToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :every_user_id, :string
    add_column :users, :name, :string
    add_column :users, :avatar_url, :string
    add_index :users, :every_user_id, unique: true
    change_column_null :users, :password_digest, true
  end
end
