# frozen_string_literal: true

require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:every_ana) }

  test "index lists active categories in position order and retired ones apart" do
    get categories_path

    assert_response :success
    assert_inertia_component "categories/index"
    assert_equal [ "bug", "billing", "feature request", "onboarding", "praise", "other" ],
      inertia.props[:categories].map { |category| category[:name] }
    assert_equal %w[pricing], inertia.props[:retired_categories].map { |category| category[:name] }
    assert_equal categories(:bug).items.count, inertia.props[:categories].first[:item_count]
  end

  test "create adds a category at the end of the list" do
    post categories_path, params: { category: { name: "security", description: "Account safety." } }

    assert_redirected_to categories_path
    category = Category.find_by!(name: "security")
    assert_equal 8, category.position
    assert_includes Category.active, category
  end

  test "a duplicate category name shows a validation error" do
    assert_no_difference -> { Category.count } do
      post categories_path, params: { category: { name: "bug" } }
    end

    follow_redirect!
    assert_equal [ "has already been taken" ], inertia.props[:errors]["name"]
  end

  test "update renames and reorders a category" do
    patch category_path(categories(:other)), params: { category: { name: "misc", position: "0" } }

    assert_redirected_to categories_path
    assert_equal "misc", categories(:other).reload.name
    assert_equal 0, categories(:other).position
  end

  test "a blank name is rejected on update" do
    patch category_path(categories(:other)), params: { category: { name: "" } }

    follow_redirect!
    assert_equal [ "can't be blank" ], inertia.props[:errors]["name"]
    assert_equal "other", categories(:other).reload.name
  end

  test "retiring a category hides it from new classification but keeps it on old items" do
    item = items(:angry_slack)
    category = item.category

    patch retire_category_path(category)

    assert_redirected_to categories_path
    assert category.reload.retired?
    assert_not_includes Category.active, category
    assert_equal category, item.reload.category

    follow_redirect!
    assert_includes inertia.props[:retired_categories].map { |row| row[:name] }, category.name
  end

  test "restore brings a retired category back" do
    patch restore_category_path(categories(:pricing))

    assert_not categories(:pricing).reload.retired?
  end
end
