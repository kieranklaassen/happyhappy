require "test_helper"

class ProductOverviewsControllerTest < ActionDispatch::IntegrationTest
  include AnomalyHelper

  setup do
    sign_in_as users(:every_ana)
    @product = products(:cora)
  end

  test "requires sign in" do
    sign_out
    get product_overview_path(@product)

    assert_redirected_to new_session_path
  end

  test "returns daily counts per sentiment for 30 days" do
    travel_to Time.zone.local(2026, 9, 24, 15) do
      items(:angry_slack).update_columns(created_at: 2.hours.ago)
      items(:claimed_intercom).update_columns(created_at: 1.day.ago)
      items(:handled_email).update_columns(created_at: 29.days.ago)
      create_item(sentiment: "praise", created_at: 1.day.ago)
      create_item(sentiment: nil, created_at: 1.day.ago)
      create_item(sentiment: "complaint", created_at: 31.days.ago)
      create_item(sentiment: "complaint", created_at: 1.hour.ago, relevant: false)

      get product_overview_path(@product)
    end

    assert_response :success
    assert_inertia_component "products/overview"
    days = inertia.props[:days]
    assert_equal 30, days.size
    assert_equal "2026-08-26", days.first[:date]
    assert_equal "2026-09-24", days.last[:date]
    assert_equal({ date: "2026-09-24", complaint: 1, praise: 0, question: 0, neutral: 0, total: 1 }, days.last.symbolize_keys)
    assert_equal({ date: "2026-09-23", complaint: 1, praise: 1, question: 0, neutral: 0, total: 3 }, days[-2].symbolize_keys)
    assert_equal({ date: "2026-08-26", complaint: 0, praise: 0, question: 1, neutral: 0, total: 1 }, days.first.symbolize_keys)
    assert_equal({ complaint: 2, praise: 1, question: 1, neutral: 0, total: 5 }, inertia.props[:totals].symbolize_keys)
  end

  test "lists notable complaints by anger and praise by praise probability" do
    calm = create_item(sentiment: "complaint", anger_probability: 0.2)
    create_item(sentiment: "praise", sentiment_probability: 0.99, author_handle: "fan")
    old = create_item(sentiment: "complaint", anger_probability: 0.99, created_at: 40.days.ago)

    get product_overview_path(@product)

    complaints = inertia.props[:notable_complaints].map { |item| item[:id] }
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id, calm.id ], complaints
    assert_not_includes complaints, old.id
    assert_equal [ "fan" ], inertia.props[:notable_praise].map { |item| item[:author] }
    assert_equal({ id: @product.id, name: "Cora", slug: "cora", retired: false }, inertia.props[:product].symbolize_keys)
  end

  test "a quiet product has zero counts and no notable items" do
    get product_overview_path(products(:sparkle))

    assert_equal 30, inertia.props[:days].size
    assert_equal 1, inertia.props[:totals][:total]

    items(:retired_product_slack).update_columns(created_at: 40.days.ago)
    get product_overview_path(products(:lex))
    assert_equal 0, inertia.props[:totals][:total]
    assert_equal [], inertia.props[:notable_complaints]
    assert inertia.props[:product][:retired]
  end

  test "finds the product by slug" do
    get product_overview_path("spiral")

    assert_equal "Spiral", inertia.props[:product][:name]
  end

  test "a missing product is not found" do
    get product_overview_path("nope")

    assert_response :not_found
  end

  private

  def create_item(sentiment:, created_at: Time.current, relevant: true, **attributes)
    @sequence = (@sequence || 0) + 1
    Item.create!(source: sources(:slack_community), product: @product, thread_key: "overview-#{@sequence}",
      sentiment: sentiment, relevant: relevant, last_message_at: created_at, created_at: created_at, **attributes)
  end

  test "lists the product's anomalies from the last 30 days, newest window first" do
    older = create_anomaly!(status: :ended, historical: true, window_start: 20.days.ago, window_end: 20.days.ago + 1.day,
      granularity: "day", metric: "volume", dimension: nil, ended_at: 1.day.ago)
    newer = create_anomaly!(source: sources(:slack_community))
    create_anomaly!(window_start: 40.days.ago, window_end: 40.days.ago + 1.hour, status: :ended, ended_at: 39.days.ago)
    create_anomaly!(product: products(:spiral))

    get product_overview_path(@product)

    anomalies = inertia.props[:anomalies]
    assert_equal [ newer.id, older.id ], anomalies.map { |anomaly| anomaly["id"] }
    assert_equal "Every community Slack", anomalies.first.dig("source", "name")
    assert anomalies.last["historical"]
    assert_equal "Message volume", anomalies.last["label"]
  end
end
