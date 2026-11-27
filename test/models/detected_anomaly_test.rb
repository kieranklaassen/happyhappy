require "test_helper"

class DetectedAnomalyTest < ActiveSupport::TestCase
  include AnomalyHelper

  test "validates metric, granularity, polarity, status, and required timestamps" do
    anomaly = build_anomaly
    assert anomaly.valid?, anomaly.errors.full_messages.to_sentence

    invalid = build_anomaly(
      metric: "unknown_metric",
      granularity: "week",
      polarity: "mixed",
      status: "paused",
      window_start: nil,
      window_end: nil,
      first_seen_at: nil,
      last_seen_at: nil
    )

    refute invalid.valid?
    %i[metric granularity polarity status window_start window_end first_seen_at last_seen_at].each do |attr|
      assert invalid.errors.key?(attr), "expected validation error on #{attr}"
    end
  end

  test "severity is required and validated only for negative anomalies" do
    DetectedAnomaly::SEVERITIES.each do |severity|
      assert build_anomaly(polarity: "negative", severity: severity, highlight: nil).valid?
    end

    missing = build_anomaly(polarity: "negative", severity: nil, highlight: nil)
    refute missing.valid?
    assert missing.errors.key?(:severity)

    unknown = build_anomaly(polarity: "negative", severity: "critical", highlight: nil)
    refute unknown.valid?
    assert unknown.errors.key?(:severity)

    positive_with_severity = build_anomaly(polarity: "positive", severity: "low", highlight: "big")
    refute positive_with_severity.valid?
    assert positive_with_severity.errors.key?(:severity)

    neutral_with_severity = build_anomaly(polarity: "neutral", severity: "low", highlight: nil)
    refute neutral_with_severity.valid?
    assert neutral_with_severity.errors.key?(:severity)
  end

  test "highlight is required and validated only for positive anomalies" do
    DetectedAnomaly::HIGHLIGHTS.each do |highlight|
      assert build_anomaly(polarity: "positive", severity: nil, highlight: highlight).valid?
    end

    missing = build_anomaly(polarity: "positive", severity: nil, highlight: nil)
    refute missing.valid?
    assert missing.errors.key?(:highlight)

    unknown = build_anomaly(polarity: "positive", severity: nil, highlight: "massive")
    refute unknown.valid?
    assert unknown.errors.key?(:highlight)

    negative_with_highlight = build_anomaly(polarity: "negative", severity: "high", highlight: "big")
    refute negative_with_highlight.valid?
    assert negative_with_highlight.errors.key?(:highlight)

    neutral_with_highlight = build_anomaly(polarity: "neutral", severity: nil, highlight: "notable")
    refute neutral_with_highlight.valid?
    assert neutral_with_highlight.errors.key?(:highlight)
  end

  test "neutral anomalies allow neither severity nor highlight" do
    neutral = build_anomaly(polarity: "neutral", severity: nil, highlight: nil)

    assert neutral.valid?, neutral.errors.full_messages.to_sentence
  end

  test "recent_first orders by window_end descending and breaks ties by id descending" do
    now = Time.current.change(usec: 0)
    older = create_anomaly!(window_start: now - 3.hours, window_end: now - 2.hours)
    tie_first = create_anomaly!(window_start: now - 1.hour, window_end: now)
    tie_second = create_anomaly!(window_start: now - 1.hour, window_end: now)

    assert_equal [ tie_second, tie_first, older ], DetectedAnomaly.recent_first.to_a
  end

  test "grade assigns polarity and severity or highlight across negative, positive, and neutral inputs" do
    assert_equal(
      { polarity: "negative", severity: "low", highlight: nil },
      DetectedAnomaly.grade(metric: "complaint_share", dimension: nil, item_ids: [], level: 0)
    )
    assert_equal(
      { polarity: "negative", severity: "medium", highlight: nil },
      DetectedAnomaly.grade(metric: "mean_anger", dimension: nil, item_ids: [], level: 1)
    )
    assert_equal(
      { polarity: "negative", severity: "high", highlight: nil },
      DetectedAnomaly.grade(metric: "category_volume", dimension: categories(:bug).id.to_s, item_ids: [], level: 2)
    )

    assert_equal(
      { polarity: "positive", severity: nil, highlight: "notable" },
      DetectedAnomaly.grade(metric: "mood_share", dimension: "beaming", item_ids: [], level: 0)
    )
    assert_equal(
      { polarity: "positive", severity: nil, highlight: "big" },
      DetectedAnomaly.grade(metric: "mood_share", dimension: "beaming", item_ids: [], level: 1)
    )
    assert_equal(
      { polarity: "positive", severity: nil, highlight: "huge" },
      DetectedAnomaly.grade(metric: "category_volume", dimension: categories(:praise).id.to_s, item_ids: [], level: 2)
    )

    assert_equal(
      { polarity: "neutral", severity: nil, highlight: nil },
      DetectedAnomaly.grade(metric: "volume", dimension: nil, item_ids: [], level: 2)
    )
    assert_equal(
      { polarity: "negative", severity: "high", highlight: nil },
      DetectedAnomaly.grade(metric: "volume", dimension: nil, item_ids: [ items(:angry_slack).id ], level: 2)
    )
    assert_equal(
      { polarity: "positive", severity: nil, highlight: "notable" },
      DetectedAnomaly.grade(metric: "volume", dimension: nil, item_ids: [ items(:praise_discord).id ], level: 0)
    )
  end

  test "slack_alertable? requires active, non-historical, negative, high-severity, all-sources, and no product alert channel" do
    assert create_anomaly!.slack_alertable?

    refute create_anomaly!(status: "ended", ended_at: Time.current).slack_alertable?
    refute create_anomaly!(historical: true).slack_alertable?
    refute create_anomaly!(polarity: "positive", severity: nil, highlight: "huge").slack_alertable?
    refute create_anomaly!(polarity: "neutral", severity: nil, highlight: nil).slack_alertable?
    refute create_anomaly!(severity: "medium").slack_alertable?
    refute create_anomaly!(severity: "low").slack_alertable?
    refute create_anomaly!(source: sources(:slack_community)).slack_alertable?

    products(:cora).update!(alert_channel_id: "C0AGCDCD6KG")
    refute create_anomaly!.slack_alertable?
  end

  test "incident_worthy? is true only for active, non-historical, negative anomalies" do
    assert create_anomaly!.incident_worthy?
    assert create_anomaly!(severity: "low", source: sources(:slack_community)).incident_worthy?

    refute create_anomaly!(status: "ended", ended_at: Time.current).incident_worthy?
    refute create_anomaly!(historical: true).incident_worthy?
    refute create_anomaly!(polarity: "positive", severity: nil, highlight: "big").incident_worthy?
    refute create_anomaly!(polarity: "neutral", severity: nil, highlight: nil).incident_worthy?
  end

  test "resolved?, positive?, negative?, and strength reflect anomaly state" do
    negative_low = build_anomaly(polarity: "negative", severity: "low")
    negative_medium = build_anomaly(polarity: "negative", severity: "medium")
    negative_high = build_anomaly(polarity: "negative", severity: "high", resolved_at: Time.current)
    positive_notable = build_anomaly(polarity: "positive", severity: nil, highlight: "notable")
    positive_big = build_anomaly(polarity: "positive", severity: nil, highlight: "big")
    positive_huge = build_anomaly(polarity: "positive", severity: nil, highlight: "huge")
    neutral = build_anomaly(polarity: "neutral", severity: nil, highlight: nil)

    refute negative_low.resolved?
    assert negative_high.resolved?

    assert negative_low.negative?
    refute negative_low.positive?

    assert positive_notable.positive?
    refute positive_notable.negative?

    refute neutral.positive?
    refute neutral.negative?

    assert_equal 0, negative_low.strength
    assert_equal 1, negative_medium.strength
    assert_equal 2, negative_high.strength
    assert_equal 0, positive_notable.strength
    assert_equal 1, positive_big.strength
    assert_equal 2, positive_huge.strength
    assert_equal 0, neutral.strength
  end

  test "category resolves only for category_volume metrics with an existing category" do
    bug = categories(:bug)

    assert_equal bug, build_anomaly(metric: "category_volume", dimension: bug.id.to_s).category
    assert_nil build_anomaly(metric: "category_volume", dimension: "999999999").category
    assert_nil build_anomaly(metric: "volume", dimension: bug.id.to_s).category
    assert_nil build_anomaly(metric: "mood_share", dimension: "beaming").category
  end

  test "label formats all five metrics including a missing category fallback" do
    assert_equal "Message volume", build_anomaly(metric: "volume", dimension: nil).label
    assert_equal "Complaint share", build_anomaly(metric: "complaint_share", dimension: nil).label
    assert_equal "Mean anger", build_anomaly(metric: "mean_anger", dimension: nil).label
    assert_equal "Beaming customers", build_anomaly(metric: "mood_share", dimension: "beaming").label
    assert_equal "Bug messages", build_anomaly(metric: "category_volume", dimension: categories(:bug).id.to_s).label
    assert_equal(
      "Feature request messages",
      build_anomaly(metric: "category_volume", dimension: categories(:feature_request).id.to_s).label
    )
    assert_equal "Category messages", build_anomaly(metric: "category_volume", dimension: "999999999").label
  end

  test "share? is true for ratio metrics and false for count metrics" do
    assert build_anomaly(metric: "complaint_share", dimension: nil).share?
    assert build_anomaly(metric: "mean_anger", dimension: nil).share?
    assert build_anomaly(metric: "mood_share", dimension: "furious").share?

    refute build_anomaly(metric: "volume", dimension: nil).share?
    refute build_anomaly(metric: "category_volume", dimension: categories(:bug).id.to_s).share?
  end

  test "end! marks an active anomaly ended and leaves an already-ended anomaly unchanged" do
    anomaly = create_anomaly!
    first_end = 10.minutes.ago.change(usec: 0)

    anomaly.end!(at: first_end)

    assert_predicate anomaly.reload, :ended?
    assert_equal first_end, anomaly.ended_at

    anomaly.end!(at: Time.current)

    assert_equal first_end, anomaly.reload.ended_at
  end

  test "end! defaults ended_at to current time" do
    freeze_time do
      anomaly = create_anomaly!
      anomaly.end!

      assert_predicate anomaly.reload, :ended?
      assert_equal Time.current, anomaly.ended_at
    end
  end

  test "to_props serializes fields with rounding, ISO8601 timestamps, and optional associations" do
    now = Time.zone.parse("2026-06-15 12:30:00 UTC")
    window_start = now - 1.hour
    cora = products(:cora)

    plain = create_anomaly!(
      product: cora,
      source: nil,
      metric: "complaint_share",
      dimension: nil,
      granularity: "hour",
      window_start: window_start,
      window_end: now,
      expected: 0.12345,
      actual: 0.67891,
      z_score: 4.567,
      polarity: "negative",
      severity: "high",
      highlight: nil,
      historical: false,
      item_ids: [ items(:angry_slack).id ],
      first_seen_at: window_start + 15.minutes,
      last_seen_at: now
    )

    assert_equal(
      {
        id: plain.id,
        product: { id: cora.id, slug: cora.slug, name: cora.name },
        source: nil,
        metric: "complaint_share",
        dimension: nil,
        label: "Complaint share",
        granularity: "hour",
        window_start: window_start.iso8601,
        window_end: now.iso8601,
        expected: 0.123,
        actual: 0.679,
        share: true,
        z_score: 4.57,
        polarity: "negative",
        severity: "high",
        highlight: nil,
        status: "active",
        historical: false,
        item_ids: [ items(:angry_slack).id ],
        first_seen_at: (window_start + 15.minutes).iso8601,
        last_seen_at: now.iso8601,
        ended_at: nil,
        incident_id: nil,
        resolved_at: nil
      },
      plain.to_props
    )

    source = sources(:slack_community)
    ended_at = now + 5.minutes
    resolved_at = now + 10.minutes
    incident = Incident.create!(product: cora, opened_at: window_start, last_anomaly_at: now)
    attached = create_anomaly!(
      product: cora,
      source: source,
      incident: incident,
      status: "ended",
      ended_at: ended_at,
      resolved_at: resolved_at
    )

    props = attached.to_props
    assert_equal({ id: source.id, kind: source.kind, name: source.name }, props[:source])
    assert_equal incident.id, props[:incident_id]
    assert_equal ended_at.iso8601, props[:ended_at]
    assert_equal resolved_at.iso8601, props[:resolved_at]
    assert_equal "ended", props[:status]
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
      item_ids: [ items(:angry_slack).id ],
      first_seen_at: now,
      last_seen_at: now
    }.merge(attributes))
  end
end
