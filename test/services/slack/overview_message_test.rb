require "test_helper"

class Slack::OverviewMessageTest < ActiveSupport::TestCase
  include AnomalyHelper

  setup do
    @zone = "America/Los_Angeles"
    @day = Date.current - 5
    @noon = @day.in_time_zone(@zone).noon
  end

  test "covers every product: mood, per-product counts, needs attention by actionability, anomalies, and praise" do
    urgent = add_item(product: products(:sparkle), sentiment: "complaint", actionability: 0.95, handle: "wants_refund", body: "Please refund my Sparkle charge")
    add_item(product: products(:cora), sentiment: "question", actionability: 0.6, handle: "how_do_i", body: "How do I snooze Brief?")
    add_item(product: products(:cora), sentiment: "complaint", actionability: 0.2, handle: "just_venting")
    fan = add_item(product: products(:spiral), sentiment: "praise", sentiment_probability: 0.98, actionability: 0.1, handle: "spiral_fan", body: "Spiral nailed my voice")
    add_item(product: products(:cora), sentiment: "relieved", actionability: 0.1, handle: "fixed_now")
    add_item(product: products(:cora), sentiment: "complaint", relevant: false, handle: "off_topic")
    add_item(product: products(:cora), sentiment: "complaint", occurred_at: @noon - 2.days, handle: "old_news")

    create_anomaly!(product: products(:spiral), metric: "mood_share", dimension: "beaming", polarity: "positive",
      severity: nil, highlight: "big", expected: 0.1, actual: 0.4, z_score: 6, window_start: @noon - 1.hour, window_end: @noon)
    create_anomaly!(product: products(:sparkle), dimension: categories(:billing).id.to_s, expected: 0.2, actual: 8,
      window_start: @noon - 1.hour, window_end: @noon)
    create_anomaly!(product: products(:sparkle), source: sources(:intercom_inbox), dimension: categories(:billing).id.to_s,
      expected: 0.2, actual: 8, window_start: @noon - 1.hour, window_end: @noon)
    create_anomaly!(product: products(:cora), historical: true, status: "ended", ended_at: @noon, window_start: @noon - 1.hour, window_end: @noon)

    payload = overview.to_h
    text = rendered(payload)

    assert_equal "happyhappy daily overview for #{@day.to_fs(:long)}", payload[:text]
    assert_includes text, "5 items with new customer messages"
    assert_includes text, "Complaint: 2  |  Praise: 1  |  Question: 1  |  Neutral: 0  |  Relieved: 1"
    assert_includes text, "*Cora*: 3 items · 1 complaint"
    assert_includes text, "*Sparkle*: 1 item · 1 complaint · 1 act now"
    assert_includes text, "*Spiral*: 1 item · 1 praise"

    attention = section(payload, "*Needs attention*")
    assert_operator attention.index("wants_refund"), :<, attention.index("how_do_i")
    assert_includes attention, "act now, 95%"
    assert_includes attention, "/items/#{urgent.id}"
    assert_not_includes attention, "just_venting"

    unusual = section(payload, "*Unusual activity*")
    assert_equal 2, unusual.lines.size, "per-source and historical rows stay out"
    assert_match(/\A:warning: \*Sparkle\*: billing messages spiked \(8 vs about 0\.2 usual, high\)/, unusual.lines.first)
    assert_includes unusual.lines.last, ":sunny: Good news for *Spiral*: beaming customers up (40% vs about 10% usual)"

    praise = section(payload, "*Standout praise*")
    assert_includes praise, "spiral_fan"
    assert_includes praise, "&gt; Spiral nailed my voice"
    assert_includes praise, "/items/#{fan.id}"

    %w[off_topic old_news].each { |handle| assert_not_includes text, handle }
  end

  test "a day without feedback says it was quiet" do
    payload = overview.to_h

    assert_equal 1, payload[:blocks].size
    assert_includes rendered(payload), "Quiet day: no new customer feedback."
  end

  test "the day is the calendar day in the given time zone" do
    add_item(product: products(:cora), sentiment: "question", handle: "late_night", occurred_at: @day.in_time_zone(@zone).end_of_day - 1.minute)
    add_item(product: products(:cora), sentiment: "question", handle: "next_morning", occurred_at: @day.in_time_zone(@zone).end_of_day + 1.minute)

    text = rendered(overview.to_h)

    assert_includes text, "1 item with new customer messages"
  end

  private

  def overview
    Slack::OverviewMessage.new(@day, time_zone: @zone)
  end

  def rendered(payload)
    payload[:blocks].map { |block| block.dig(:text, :text) || block[:elements].sole[:text] }.join("\n")
  end

  def section(payload, heading)
    payload[:blocks].filter_map { |block| block.dig(:text, :text) }.find { |text| text.start_with?(heading) }.delete_prefix("#{heading}\n")
  end

  def add_item(product:, sentiment:, handle:, actionability: nil, sentiment_probability: 0.9, relevant: true,
    occurred_at: @noon, body: "Message from #{handle}")
    item = Item.create!(source: sources(:intercom_inbox), thread_key: "overview-#{SecureRandom.hex(4)}",
      author_handle: handle, product: product, sentiment: sentiment, sentiment_probability: sentiment_probability,
      relevant: relevant, actionability: actionability,
      actionability_band: Actionability.band(score: actionability, relevant: relevant), last_message_at: occurred_at)
    item.messages.create!(source: item.source, external_id: SecureRandom.hex(8), body: body, occurred_at: occurred_at)
    item
  end
end
