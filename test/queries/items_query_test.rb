require "test_helper"

class ItemsQueryTest < ActiveSupport::TestCase
  include AnomalyHelper

  def results(**filters)
    ItemsQuery.new(**filters).call.to_a
  end

  test "with no filters returns relevant items, most recent first" do
    items = results

    assert_equal Item.relevant.recent_first.to_a, items
    assert_not_includes items, items(:not_relevant_slack)
  end

  test "filtering by product and complaint returns only matching items" do
    items = results(product: products(:cora).id, sentiment: "complaint")

    assert_equal [ items(:angry_slack), items(:claimed_intercom) ], items
  end

  test "product accepts a slug and a list" do
    assert_equal [ items(:praise_discord) ], results(product: "spiral")
    assert_equal [ items(:needs_review_x), items(:praise_discord) ].to_set,
      results(product: [ "spiral", products(:sparkle).id.to_s ]).to_set
  end

  test "product none returns items with no product" do
    items(:angry_slack).update!(product: nil)

    assert_equal [ items(:angry_slack) ], results(product: "none")
  end

  test "filters by category id or name, status, and source" do
    assert_equal [ items(:claimed_intercom) ], results(category: categories(:billing).id)
    assert_equal [ items(:claimed_intercom) ], results(category: "billing")
    assert_equal [ items(:handled_email) ], results(status: "handled")
    assert_equal [ items(:praise_discord) ], results(source: sources(:discord_spiral).id)
    assert_equal [ items(:angry_slack), items(:retired_product_slack) ], results(source_kind: "slack")
  end

  test "filters by time range preset and explicit bounds" do
    assert_equal [ items(:needs_review_x), items(:angry_slack), items(:claimed_intercom) ], results(range: "24h")
    assert_includes results(range: "7d"), items(:handled_email)
    assert_equal [ items(:praise_discord) ],
      results(since: 26.hours.ago.iso8601, until: 20.hours.ago.iso8601)
  end

  test "filters by needs review and overdue" do
    items(:claimed_intercom).update!(overdue: true)

    assert_equal [ items(:needs_review_x) ], results(needs_review: "true")
    assert_equal [ items(:claimed_intercom) ], results(overdue: true)
  end

  test "not relevant items are hidden by default and shown with the relevance filter" do
    assert_not_includes results, items(:not_relevant_slack)
    assert_equal [ items(:not_relevant_slack) ], results(relevance: "not_relevant")
    assert_includes results(relevance: "all"), items(:not_relevant_slack)
    assert_equal Item.count, results(relevance: "all").size
  end

  test "blank filters are ignored" do
    assert_equal results, results(product: "", sentiment: nil, status: [ "" ], range: "", needs_review: "0")
  end

  test "filters reports the normalized filters that were applied" do
    query = ItemsQuery.new(product: "cora", sentiment: "complaint", needs_review: "1", status: "", range: "7d")

    assert_equal({ product: [ "cora" ], sentiment: [ "complaint" ], range: "7d", needs_review: true, relevance: "relevant" },
      query.filters)
  end

  test "from_params reads the known filters from request parameters and ignores the rest" do
    params = ActionController::Parameters.new(sentiment: "praise", product: [ "spiral" ], page: "2", controller: "items")

    assert_equal [ items(:praise_discord) ], ItemsQuery.from_params(params).call.to_a
  end

  test "invalid values raise InvalidFilter naming the filter" do
    { sentiment: "furious", status: "open", range: "1y", relevance: "some", since: "yesterday",
      needs_review: "maybe" }.each do |filter, value|
      error = assert_raises(ItemsQuery::InvalidFilter) { ItemsQuery.new(filter => value) }
      assert_equal filter, error.filter
      assert_match filter.to_s, error.message
    end
  end

  test "unknown filters raise InvalidFilter" do
    error = assert_raises(ItemsQuery::InvalidFilter) { ItemsQuery.new(colour: "red") }

    assert_equal :colour, error.filter
  end

  test "anomaly narrows to the items behind active anomalies, or behind one anomaly" do
    active = create_anomaly!(item_ids: [ items(:angry_slack).id, items(:claimed_intercom).id ])
    ended = create_anomaly!(item_ids: [ items(:praise_discord).id ], status: :ended, ended_at: Time.current)

    assert_equal [ items(:angry_slack), items(:claimed_intercom) ], results(anomaly: "active")
    assert_equal [ items(:praise_discord) ], results(anomaly: ended.id.to_s)
    assert_equal [ items(:angry_slack) ], results(anomaly: active.id, sentiment: "complaint", source_kind: "slack")
    assert_empty results(anomaly: "0")
  end

  test "an anomaly filter that is neither active nor an id is invalid" do
    error = assert_raises(ItemsQuery::InvalidFilter) { ItemsQuery.new(anomaly: "spiky") }
    assert_equal :anomaly, error.filter
  end
end
