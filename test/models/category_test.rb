require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "orders by position" do
    assert_equal [ "bug", "billing", "feature request", "onboarding", "praise", "other" ],
      Category.active.ordered.pluck(:name)
  end

  test "search blurb defaults to the name and stays short" do
    category = Category.create!(name: "security")
    assert_equal "security", category.search_blurb

    category.search_blurb = "x" * (SearchBlurb::MAX_LENGTH + 1)
    refute category.valid?
  end

  test "requires a unique name" do
    refute Category.new(name: "bug").valid?
  end

  test "retiring hides it from active categories but keeps old items labeled" do
    category = categories(:pricing)

    assert category.retired?
    assert_not_includes Category.active, category
    assert_equal category, items(:retired_product_slack).category
  end
end
