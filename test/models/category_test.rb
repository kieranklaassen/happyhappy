require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "orders by position" do
    assert_equal [ "bug", "billing", "feature request", "onboarding", "praise", "other" ],
      Category.active.ordered.pluck(:name)
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
