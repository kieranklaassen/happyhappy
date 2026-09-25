class AddSearchBlurbToProductsAndCategories < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :search_blurb, :string
    add_column :categories, :search_blurb, :string

    execute "UPDATE products SET search_blurb = substr(name, 1, 40) WHERE search_blurb IS NULL"
    execute "UPDATE categories SET search_blurb = substr(name, 1, 40) WHERE search_blurb IS NULL"
  end

  def down
    remove_column :categories, :search_blurb
    remove_column :products, :search_blurb
  end
end
