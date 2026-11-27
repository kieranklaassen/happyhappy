require "test_helper"

class Slack::AnomalyAlertMessageTest < ActiveSupport::TestCase
  include AnomalyHelper

  test "to_h includes fallback text, anomaly wording, overview link, customers block, and context" do
    window_start = Time.utc(2026, 6, 15, 19, 0)
    window_end = Time.utc(2026, 6, 15, 20, 0)
    Setting.current.update!(digest_time_zone: "America/Los_Angeles")

    anomaly = create_anomaly!(
      product: products(:cora),
      metric: "category_volume",
      dimension: categories(:bug).id.to_s,
      granularity: "hour",
      window_start: window_start,
      window_end: window_end,
      expected: 0.4,
      actual: 9,
      severity: "high",
      item_ids: [ items(:angry_slack).id ]
    )

    payload = with_env("PUBLIC_BASE_URL", nil) do
      Slack::AnomalyAlertMessage.new(anomaly).to_h
    end

    assert_equal "Cora: bug messages spiked", payload[:text]
    assert_equal 3, payload[:blocks].size

    header = payload[:blocks].first.dig(:text, :text)
    assert_includes header, ":warning: *Cora*: bug messages spiked (9 vs about 0.4 usual, high)"
    assert_includes header, "<http://localhost:3000/products/#{products(:cora).id}/overview|Open the Cora overview>"

    customers = payload[:blocks].second.dig(:text, :text)
    assert customers.start_with?("*Customers behind it*\n")
    assert_includes customers, "<http://localhost:3000/items/#{items(:angry_slack).id}|ana_customer>"
    assert_includes customers, "&gt; Still nothing. Anyone from Every here?"

    context = payload[:blocks].third[:elements].sole[:text]
    assert_equal "Jun 15 12:00 to 13:00 PDT · hourly check", context
  end

  test "overview and item links use PUBLIC_BASE_URL and strip a trailing slash" do
    anomaly = create_anomaly!(product: products(:cora), item_ids: [ items(:angry_slack).id ])

    [ "https://happyhappy.every.to", "https://happyhappy.every.to/" ].each do |base_url|
      payload = with_env("PUBLIC_BASE_URL", base_url) do
        Slack::AnomalyAlertMessage.new(anomaly).to_h
      end

      header = payload[:blocks].first.dig(:text, :text)
      customers = payload[:blocks].second.dig(:text, :text)

      assert_includes header, "<https://happyhappy.every.to/products/#{products(:cora).id}/overview|Open the Cora overview>"
      assert_includes customers, "<https://happyhappy.every.to/items/#{items(:angry_slack).id}|ana_customer>"
    end
  end

  test "Customers behind it caps at EXAMPLE_COUNT, orders by actionability, and quotes the latest customer message skipping team replies" do
    now = Time.current
    low = add_item(handle: "low_priority", actionability: 0.15, body: "Minor annoyance", at: now - 40.minutes)
    third = add_item(handle: "third_priority", actionability: 0.45, body: "Third issue", at: now - 30.minutes)
    top = add_item(handle: "top_priority", actionability: 0.95, body: "First customer note", at: now - 20.minutes)
    second = add_item(handle: "second_priority", actionability: 0.80, body: "Second issue", at: now - 10.minutes)

    top.messages.create!(
      source: top.source,
      external_id: SecureRandom.uuid,
      body: "Follow-up from customer: still broken",
      occurred_at: now - 5.minutes,
      author_role: "customer"
    )
    top.messages.create!(
      source: top.source,
      external_id: SecureRandom.uuid,
      body: "Team reply: looking into this now",
      occurred_at: now - 1.minute,
      author_role: "team"
    )

    anomaly = create_anomaly!(item_ids: [ low.id, third.id, top.id, second.id ])
    customers = Slack::AnomalyAlertMessage.new(anomaly).to_h[:blocks].second.dig(:text, :text)

    assert_operator customers.index("top_priority"), :<, customers.index("second_priority")
    assert_operator customers.index("second_priority"), :<, customers.index("third_priority")
    assert_not_includes customers, "low_priority"

    assert_includes customers, "&gt; Follow-up from customer: still broken"
    assert_not_includes customers, "First customer note"
    assert_not_includes customers, "Team reply: looking into this now"
  end

  test "Customers behind it escapes customer handles and message bodies" do
    item = add_item(
      handle: "ana <@here> & co",
      actionability: 0.9,
      body: "<!channel> @here see <https://evil.example|invoice> & more"
    )

    anomaly = create_anomaly!(item_ids: [ item.id ])
    customers = Slack::AnomalyAlertMessage.new(anomaly).to_h[:blocks].second.dig(:text, :text)

    assert_includes customers, "|ana &lt;@\u200Bhere&gt; &amp; co>"
    assert_not_includes customers, "<!channel>"
    assert_not_includes customers, "<https://evil.example"
    assert_includes customers, "&gt; &lt;!channel&gt; @\u200Bhere see &lt;https://evil.example|invoice&gt; &amp; more"
  end

  test "omits the Customers behind it block when item_ids is empty" do
    anomaly = create_anomaly!(item_ids: [])
    payload = Slack::AnomalyAlertMessage.new(anomaly).to_h

    assert_equal %w[section context], payload[:blocks].map { |block| block[:type] }
    assert_not_includes JSON.generate(payload[:blocks]), "Customers behind it"
  end

  test "context line uses Setting.current.digest_zone and distinguishes hourly and daily checks" do
    Setting.current.update!(digest_time_zone: "America/New_York")

    hourly = create_anomaly!(
      granularity: "hour",
      window_start: Time.utc(2026, 1, 15, 14, 0),
      window_end: Time.utc(2026, 1, 15, 15, 0),
      item_ids: []
    )
    daily = create_anomaly!(
      granularity: "day",
      window_start: Time.utc(2026, 1, 15, 5, 0),
      window_end: Time.utc(2026, 1, 16, 5, 0),
      item_ids: []
    )

    assert_equal(
      "Jan 15 09:00 to 10:00 EST · hourly check",
      Slack::AnomalyAlertMessage.new(hourly).to_h[:blocks].last[:elements].sole[:text]
    )
    assert_equal(
      "Jan 15 00:00 to 00:00 EST · daily check",
      Slack::AnomalyAlertMessage.new(daily).to_h[:blocks].last[:elements].sole[:text]
    )
  end

  private

  def add_item(handle:, actionability:, body:, at: Time.current)
    item = Item.create!(
      source: sources(:intercom_inbox),
      thread_key: "alert-#{SecureRandom.hex(6)}",
      author_handle: handle,
      product: products(:cora),
      category: categories(:bug),
      sentiment: "complaint",
      sentiment_probability: 0.9,
      anger_probability: 0.8,
      actionability: actionability,
      actionability_band: Actionability.band(score: actionability, relevant: true),
      relevant: true,
      last_message_at: at
    )
    item.messages.create!(
      source: item.source,
      external_id: SecureRandom.uuid,
      body: body,
      occurred_at: at,
      author_role: "customer"
    )
    item
  end

  def with_env(key, value)
    had_key = ENV.key?(key)
    previous = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    had_key ? ENV[key] = previous : ENV.delete(key)
  end
end
