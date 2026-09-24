require "test_helper"

class ItemLabelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:every_ana)
    sign_in_as @user
  end

  test "requires sign in" do
    sign_out
    patch item_labels_path(items(:angry_slack)), params: { label: "sentiment", value: "praise" }

    assert_redirected_to new_session_path
    assert items(:angry_slack).reload.complaint?
  end

  test "covers F4: changing an item's product moves it in the filtered feed and writes a correction event with the user" do
    item = items(:angry_slack)
    get items_path, params: { product: "spiral" }
    assert_not_includes inertia.props[:items].map { |row| row[:id] }, item.id

    patch item_labels_path(item), params: { label: "product", value: products(:spiral).id }

    assert_redirected_to item_path(item)
    assert_equal "Product set to Spiral.", flash[:notice]
    event = item.events.last
    assert event.corrected?
    assert_equal @user, event.actor
    assert_equal %w[product Cora Spiral], event.data.values_at("label", "from", "to")

    get items_path, params: { product: "spiral" }
    assert_includes inertia.props[:items].map { |row| row[:id] }, item.id
    get items_path, params: { product: "cora" }
    assert_not_includes inertia.props[:items].map { |row| row[:id] }, item.id

    get item_path(item)
    assert inertia.props[:item][:labels][:product][:human_set]
  end

  test "clearing the product and marking not relevant read back in the notice" do
    item = items(:angry_slack)

    patch item_labels_path(item), params: { label: "product", value: "" }
    assert_equal "Product set to none.", flash[:notice]

    patch item_labels_path(item), params: { label: "relevant", value: "false" }
    assert_equal "Relevance set to not relevant.", flash[:notice]
  end

  test "an invalid correction redirects back with an alert and changes nothing" do
    item = items(:angry_slack)

    patch item_labels_path(item), params: { label: "product", value: products(:lex).id }

    assert_redirected_to item_path(item)
    assert_equal "Lex is retired", flash[:alert]
    assert_equal products(:cora), item.reload.product
  end
end
