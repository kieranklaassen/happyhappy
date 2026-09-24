require "test_helper"

class ItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:every_ana)
  end

  def item_ids
    inertia.props[:items].map { |item| item[:id] }
  end

  test "requires sign in" do
    sign_out
    get items_path

    assert_redirected_to new_session_path
  end

  test "the root redirects to the feed" do
    get root_path

    assert_redirected_to items_path
  end

  test "the feed lists relevant items most recent first with row fields" do
    get items_path

    assert_response :success
    assert_inertia_component "items/index"
    assert_equal ItemsQuery.new.call.ids, item_ids
    assert_nil inertia.props[:error]

    row = inertia.props[:items].find { |item| item[:id] == items(:angry_slack).id }
    assert_equal "Still nothing. Anyone from Every here?", row[:excerpt]
    assert_equal "ana_customer", row[:author]
    assert_equal({ id: products(:cora).id, name: "Cora", slug: "cora", retired: false }, row[:product].symbolize_keys)
    assert_equal "bug", row[:category][:name]
    assert_equal({ id: sources(:slack_community).id, name: "Every community Slack", kind: "slack" },
      row[:source].symbolize_keys)
    assert_equal "complaint", row[:sentiment]
    assert_equal "new", row[:status]
    assert_in_delta 0.86, row[:anger_probability]
    assert_equal false, row[:overdue]
  end

  test "filtering by product and complaint returns only matching items" do
    get items_path, params: { product: products(:cora).id, sentiment: "complaint" }

    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ], item_ids
    assert_equal [ products(:cora).id.to_s ], inertia.props[:filters][:product]
  end

  test "not relevant items are hidden by default and shown with the filter" do
    get items_path
    assert_not_includes item_ids, items(:not_relevant_slack).id

    get items_path, params: { relevance: "all" }
    assert_includes item_ids, items(:not_relevant_slack).id
  end

  test "an overdue item carries the overdue flag and the claiming agent" do
    items(:claimed_intercom).update!(overdue: true)

    get items_path, params: { overdue: "1" }

    row = inertia.props[:items].sole
    assert_equal items(:claimed_intercom).id, row[:id]
    assert row[:overdue]
    assert_equal "Cursor", row[:claimed_by]
  end

  test "an invalid filter renders an error state instead of a wider feed" do
    get items_path, params: { sentiment: "furious" }

    assert_response :success
    assert_equal [], inertia.props[:items]
    assert_match "sentiment", inertia.props[:error]
  end

  test "options list active products and categories plus retired ones for reading old items" do
    get items_path

    options = inertia.props[:options]
    assert_equal %w[Cora Lex Sparkle Spiral], options[:products].map { |product| product[:name] }
    assert options[:products].find { |product| product[:name] == "Lex" }[:retired]
    assert_includes options[:categories].map { |category| category[:name] }, "pricing"
    assert_equal Item.sentiments.values, options[:sentiments]
    assert_equal Item.statuses.values, options[:statuses]
    assert_equal ItemsQuery::RANGES.keys, options[:ranges]
  end

  test "paginates" do
    now = Time.current
    Item.insert_all(Array.new(ItemsController::PER_PAGE) do |index|
      { source_id: sources(:slack_community).id, source_kind: "slack", thread_key: "bulk-#{index}", status: "new",
        status_changed_at: now, last_message_at: now - index.minutes, created_at: now, updated_at: now }
    end)

    get items_path
    assert_equal ItemsController::PER_PAGE, item_ids.size
    assert_equal({ page: 1, prev_page: nil, next_page: 2 }, inertia.props[:pagination].symbolize_keys)

    get items_path, params: { page: 2 }
    assert_equal ItemsQuery.new.call.offset(ItemsController::PER_PAGE).ids, item_ids
    assert_equal({ page: 2, prev_page: 1, next_page: nil }, inertia.props[:pagination].symbolize_keys)

    get items_path, params: { page: "99999999999999999999" }
    assert_response :success
    assert_equal ItemsController::MAX_PAGE, inertia.props[:pagination][:page]
    assert_equal [], item_ids
  end

  test "the item page shows labels, messages, and the timeline in time order with actor names" do
    item = items(:needs_review_x)
    item.record_event!(:reported, actor: agents(:cursor), summary: "Replied on X.")

    get item_path(item)

    assert_response :success
    assert_inertia_component "items/show"
    props = inertia.props
    assert_equal item.id, props[:item][:id]
    assert props[:item][:needs_review]
    product = props[:item][:labels][:product]
    assert_equal "Sparkle", product[:value][:name]
    assert_in_delta 0.45, product[:probability]
    assert_equal false, product[:human_set]
    assert_equal "other", props[:item][:labels][:category][:value][:name]
    assert_equal({ value: "neutral", probability: 0.7, human_set: false }, props[:item][:labels][:sentiment].symbolize_keys)
    assert_equal [ "Trying out that new file organizer from Every. Not sure yet." ], props[:messages].map { |m| m[:body] }
    assert_equal %w[corrected reported], props[:events].map { |event| event[:kind] }
    assert_equal [ "one@example.com", "Cursor" ], props[:events].map { |event| event[:actor][:name] }
    assert_equal %w[User Agent], props[:events].map { |event| event[:actor][:type] }
    assert_equal 0.6, props[:low_confidence_threshold]
    assert_equal ItemsController::HUMAN_STATUSES, props[:options][:statuses]
  end

  test "the item page lists a retired product only when it is the item's label" do
    get item_path(items(:angry_slack))
    assert_not_includes inertia.props[:options][:products].map { |product| product[:name] }, "Lex"

    get item_path(items(:retired_product_slack))
    assert_includes inertia.props[:options][:products].map { |product| product[:name] }, "Lex"
  end

  test "a missing item is not found" do
    get item_path(id: 0)

    assert_response :not_found
  end
end
