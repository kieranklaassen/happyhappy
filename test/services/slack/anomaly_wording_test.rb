require "test_helper"

class Slack::AnomalyWordingTest < ActiveSupport::TestCase
  class Host
    include Slack::AnomalyWording

    public :anomaly_line, :anomaly_value
  end

  setup do
    @wording = Host.new
  end

  test "anomaly_line formats negative anomalies with severity, with and without a source" do
    all_sources = build_anomaly(
      product: products(:sparkle),
      source: nil,
      metric: "category_volume",
      dimension: categories(:billing).id.to_s,
      polarity: "negative",
      severity: "high",
      actual: 8,
      expected: 0.2
    )
    per_source = build_anomaly(
      product: products(:sparkle),
      source: sources(:intercom_inbox),
      metric: "category_volume",
      dimension: categories(:billing).id.to_s,
      polarity: "negative",
      severity: "medium",
      actual: 8,
      expected: 0.2
    )

    assert_equal(
      ":warning: *Sparkle*: billing messages spiked (8 vs about 0.2 usual, high)",
      @wording.anomaly_line(all_sources)
    )
    assert_equal(
      ":warning: *Sparkle*: billing messages spiked on Intercom support inbox (8 vs about 0.2 usual, medium)",
      @wording.anomaly_line(per_source)
    )
  end

  test "anomaly_line formats positive anomalies as good news without severity, with and without a source" do
    all_sources = build_anomaly(
      product: products(:spiral),
      source: nil,
      metric: "mood_share",
      dimension: "beaming",
      polarity: "positive",
      severity: nil,
      highlight: "big",
      actual: 0.4,
      expected: 0.1
    )
    per_source = build_anomaly(
      product: products(:spiral),
      source: sources(:discord_spiral),
      metric: "mood_share",
      dimension: "beaming",
      polarity: "positive",
      severity: nil,
      highlight: "huge",
      actual: 0.4,
      expected: 0.1
    )

    assert_equal(
      ":sunny: Good news for *Spiral*: beaming customers up (40% vs about 10% usual)",
      @wording.anomaly_line(all_sources)
    )
    assert_equal(
      ":sunny: Good news for *Spiral*: beaming customers up on Spiral Discord (40% vs about 10% usual)",
      @wording.anomaly_line(per_source)
    )
  end

  test "anomaly_line formats neutral anomalies plainly without emoji or severity, with and without a source" do
    all_sources = build_anomaly(
      product: products(:cora),
      source: nil,
      metric: "volume",
      dimension: nil,
      polarity: "neutral",
      severity: nil,
      highlight: nil,
      actual: 12,
      expected: 3.5
    )
    per_source = build_anomaly(
      product: products(:cora),
      source: sources(:slack_community),
      metric: "volume",
      dimension: nil,
      polarity: "neutral",
      severity: nil,
      highlight: nil,
      actual: 12,
      expected: 3.5
    )

    assert_equal(
      "*Cora*: message volume up (12 vs about 3.5 usual)",
      @wording.anomaly_line(all_sources)
    )
    assert_equal(
      "*Cora*: message volume up on Every community Slack (12 vs about 3.5 usual)",
      @wording.anomaly_line(per_source)
    )
  end

  test "anomaly_line escapes product, source, and label text" do
    category = Category.create!(name: "Billing & <Tax> @everyone", position: 99)
    anomaly = build_anomaly(
      product: Product.new(name: "Cora & <Labs> @here"),
      source: Source.new(name: "Support <VIP> & @channel"),
      metric: "category_volume",
      dimension: category.id.to_s,
      polarity: "negative",
      severity: "high",
      actual: 5,
      expected: 1
    )

    assert_equal(
      ":warning: *Cora &amp; &lt;Labs&gt; @\u200Bhere*: billing &amp; &lt;Tax&gt; @\u200Beveryone messages spiked on Support &lt;VIP&gt; &amp; @\u200Bchannel (5 vs about 1 usual, high)",
      @wording.anomaly_line(anomaly)
    )
  end

  test "anomaly_value formats share metrics as percentages and count metrics without trailing .0" do
    share_anomaly = build_anomaly(metric: "complaint_share", dimension: nil)
    count_anomaly = build_anomaly(metric: "volume", dimension: nil)

    assert_equal "43%", @wording.anomaly_value(share_anomaly, 0.426)
    assert_equal "10%", @wording.anomaly_value(share_anomaly, 0.1)
    assert_equal "0%", @wording.anomaly_value(share_anomaly, 0)

    assert_equal "8", @wording.anomaly_value(count_anomaly, 8)
    assert_equal "8", @wording.anomaly_value(count_anomaly, 8.0)
    assert_equal "8", @wording.anomaly_value(count_anomaly, 8.04)
    assert_equal "0", @wording.anomaly_value(count_anomaly, 0.0)
    assert_equal "0.2", @wording.anomaly_value(count_anomaly, 0.2)
    assert_equal "1.3", @wording.anomaly_value(count_anomaly, 1.26)
    assert_equal "1.2", @wording.anomaly_value(count_anomaly, 1.24)
  end

  private

  def build_anomaly(**attributes)
    now = Time.current
    DetectedAnomaly.new({
      product: products(:cora),
      metric: "category_volume",
      dimension: categories(:bug).id.to_s,
      granularity: "hour",
      window_start: now - 1.hour,
      window_end: now,
      expected: 0.4,
      actual: 9,
      z_score: 12,
      polarity: "negative",
      severity: "high",
      item_ids: [],
      first_seen_at: now,
      last_seen_at: now
    }.merge(attributes))
  end
end
