require "test_helper"

# F4 end to end: a team member corrects an item's product from the item page;
# the feed moves the item, the timeline records who corrected it, and later
# classifications (fake classifier) keep the human's label.
class CorrectionFlowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:every_ana)
    @item = items(:angry_slack)
  end

  test "covers F4: a correction changes the feed result and the timeline" do
    assert_includes feed_ids(product: "cora"), @item.id
    assert_not_includes feed_ids(product: "spiral"), @item.id

    patch item_labels_path(@item), params: { label: "product", value: products(:spiral).id }
    assert_redirected_to item_path(@item)

    assert_not_includes feed_ids(product: "cora"), @item.id
    assert_includes feed_ids(product: "spiral"), @item.id

    get item_path(@item)
    product = inertia.props[:item][:labels][:product]
    assert_equal "Spiral", product[:value][:name]
    assert product[:human_set]
    correction = inertia.props[:events].last
    assert_equal "corrected", correction[:kind]
    assert_equal({ type: "User", name: users(:every_ana).name }, correction[:actor].symbolize_keys)

    use_fake_classifier(product: "cora", product_probability: 0.97)
    message = @item.messages.create!(source: @item.source, external_id: "C0COMMUNITY:1727190500.000100",
      body: "Still no undo for the Cora archive.", occurred_at: Time.current)
    perform_enqueued_jobs { ClassifyMessageJob.perform_later(message) }

    assert_equal products(:spiral), @item.reload.product
    assert_includes feed_ids(product: "spiral"), @item.id
  end

  test "covers F4: marking an item not relevant removes it from the default feed and keeps it under all" do
    patch item_labels_path(@item), params: { label: "relevant", value: "false" }

    assert_not_includes feed_ids, @item.id
    assert_includes feed_ids(relevance: "all"), @item.id
    assert_equal "corrected", @item.events.last.kind
  end

  private

  def feed_ids(**filters)
    get items_path(filters)
    assert_response :success
    inertia.props[:items].map { |row| row[:id] }
  end
end
