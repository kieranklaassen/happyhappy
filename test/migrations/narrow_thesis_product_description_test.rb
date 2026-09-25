require "test_helper"
require Rails.root.join("db/migrate/20260925041000_narrow_thesis_product_description")

class NarrowThesisProductDescriptionTest < ActiveSupport::TestCase
  test "narrows untouched descriptions, leaves edited ones, and reverses" do
    from, to = NarrowThesisProductDescription::CHANGES.fetch("thesis-2027")
    thesis = Product.create!(name: "Thesis: 2027", slug: "thesis-2027", description: from)
    edited = Product.create!(name: "Every", slug: "every", description: "Edited by hand.")
    migration = NarrowThesisProductDescription.new

    ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
    assert_equal to, thesis.reload.description
    assert_equal "Edited by hand.", edited.reload.description

    ActiveRecord::Migration.suppress_messages { migration.migrate(:down) }
    assert_equal from, thesis.reload.description
  end
end
