require "test_helper"

class Anomalies::DetectTest < ActiveSupport::TestCase
  include AnomalyHelper
  include WebhookEndpointHelper
  include ActiveJob::TestHelper

  setup { @now = anomaly_now }

  def hourly_baseline!
    steady_series!(ending: @now - 1.hour, step: 1.hour, windows: 12, category: categories(:other))
  end

  def burst!(count, ending: @now, category: categories(:bug), **attributes)
    count.times do |index|
      customer_message!(at: ending - 1.hour + (index + 1).minutes, sentiment: "complaint", anger: 0.7,
        category: category, **attributes)
    end
  end

  def detect(now: @now, granularity: "hour")
    Anomalies::Detect.call(granularity: granularity, now: now)
  end

  def bug_anomalies(source: nil)
    DetectedAnomaly.where(product: products(:cora), source: source, metric: "category_volume",
      dimension: categories(:bug).id.to_s)
  end

  test "a burst of bug reports on Cora opens one active anomaly per series" do
    hourly_baseline!
    burst!(8)

    detect

    anomaly = bug_anomalies.sole
    assert_predicate anomaly, :active?
    assert_not anomaly.historical?
    assert_equal "hour", anomaly.granularity
    assert_equal [ @now - 1.hour, @now ], [ anomaly.window_start, anomaly.window_end ]
    assert_in_delta 0.0, anomaly.expected
    assert_in_delta 8.0, anomaly.actual
    assert_equal "high", anomaly.severity
    assert_equal 8, anomaly.item_ids.size
    assert_equal @now, anomaly.first_seen_at
    assert_equal 1, bug_anomalies(source: sources(:slack_community)).count
    assert DetectedAnomaly.exists?(product: products(:cora), source: nil, metric: "volume")
    # Baseline hours hold fewer messages than the minimum count, so shares have no baseline to judge by.
    assert_not DetectedAnomaly.exists?(metric: "complaint_share")
  end

  test "the anomaly gem decides against a z-score of the baseline" do
    hourly_baseline!
    burst!(8)
    detector = Anomaly::Detector.new([ [ 1.0, 0 ], [ 2.0, 0 ], [ 1.0, 0 ], [ 2.0, 0 ] ], eps: 1.0)
    threshold = detector.probability([ detector.mean.first + 3 * detector.std.first ])

    assert detector.anomaly?([ 8.0 ], threshold)
    assert_not detector.anomaly?([ 2.0 ], threshold)

    detect
    volume = DetectedAnomaly.find_by!(product: products(:cora), source: nil, metric: "volume")
    assert_in_delta 1.5, volume.expected
    assert_in_delta 8.0, volume.actual
  end

  test "a rerun while the spike lasts updates the same row, and a normal window ends it" do
    hourly_baseline!
    burst!(8)
    detect

    burst!(14, ending: @now + 1.hour)
    detect(now: @now + 1.hour)

    anomaly = bug_anomalies.sole
    assert_predicate anomaly, :active?
    assert_equal @now + 1.hour, anomaly.window_end
    assert_in_delta 14.0, anomaly.actual
    assert_equal @now, anomaly.first_seen_at
    assert_equal @now + 1.hour, anomaly.last_seen_at
    assert_equal 22, anomaly.item_ids.size

    customer_message!(at: @now + 90.minutes, category: categories(:other))
    detect(now: @now + 2.hours)

    anomaly.reload
    assert_predicate anomaly, :ended?
    assert_equal @now + 2.hours, anomaly.ended_at
    assert_equal 1, bug_anomalies.count
  end

  test "rerunning at the same time never duplicates" do
    hourly_baseline!
    burst!(8)
    detect
    assert_no_difference -> { DetectedAnomaly.count } do
      detect
    end
  end

  test "windows with too little data and series without enough baseline are skipped" do
    hourly_baseline!
    burst!(4)
    burst!(8, product: products(:sparkle), source: sources(:x_mentions), ending: @now)

    detect

    assert_empty DetectedAnomaly.where(product: products(:cora))
    assert_empty DetectedAnomaly.where(product: products(:sparkle))
  end

  test "an anomaly stays active only while its series keeps reporting" do
    hourly_baseline!
    burst!(8)
    detect

    detect(now: @now + 4.hours)

    assert bug_anomalies.all?(&:ended?)
  end

  test "a spike in backfilled history older than the active window is ended history and sends nothing" do
    create_webhook_endpoint(events: [ DetectedAnomaly::WEBHOOK_EVENT ])
    today = @now.to_date
    20.times do |back|
      (back.even? ? 1 : 2).times do
        customer_message!(at: (today - 40 + back).beginning_of_day + 1.hour, backfilled: true, category: categories(:other))
      end
    end
    10.times do |index|
      customer_message!(at: (today - 20).beginning_of_day + index.minutes, backfilled: true, sentiment: "complaint",
        category: categories(:billing))
    end

    assert_no_difference -> { WebhookDelivery.count } do
      detect(granularity: "day")
    end

    billing = DetectedAnomaly.find_by!(product: products(:cora), source: nil, metric: "category_volume",
      dimension: categories(:billing).id.to_s, granularity: "day")
    assert_predicate billing, :ended?
    assert_predicate billing, :historical?
    assert_equal (today - 20).beginning_of_day, billing.window_start
    assert_empty DetectedAnomaly.active
  end

  test "a new active anomaly sends anomaly.detected to subscribed endpoints for its product only" do
    hourly_baseline!
    subscribed = create_webhook_endpoint(events: [ DetectedAnomaly::WEBHOOK_EVENT ], product_ids: [ products(:cora).id ])
    create_webhook_endpoint(events: [ DetectedAnomaly::WEBHOOK_EVENT ], product_ids: [ products(:spiral).id ])
    create_webhook_endpoint(events: %w[item.classified])
    bug_only = create_webhook_endpoint(events: [ DetectedAnomaly::WEBHOOK_EVENT ], category_ids: [ categories(:bug).id ])
    burst!(8)

    created = detect

    assert_equal created.size, subscribed.deliveries.count
    assert_equal 2, bug_only.deliveries.count
    assert_equal WebhookDelivery.count, subscribed.deliveries.count + bug_only.deliveries.count
    delivery = subscribed.deliveries.joins(:webhook_endpoint).find_by!("json_extract(payload, '$.anomaly.metric') = 'category_volume' AND json_extract(payload, '$.anomaly.source') IS NULL")
    assert_equal DetectedAnomaly::WEBHOOK_EVENT, delivery.event
    assert_equal bug_anomalies.sole.id, delivery.payload.dig("anomaly", "id")
    assert_match "/items?anomaly=#{bug_anomalies.sole.id}", delivery.payload.dig("anomaly", "url")
    assert_equal 8.0, delivery.payload.dig("anomaly", "actual")
    assert_enqueued_jobs WebhookDelivery.count, only: WebhookDeliveryJob
  end

  test "thresholds come from the settings record" do
    hourly_baseline!
    Setting.current.update!(anomaly_min_count: 10)
    burst!(8)

    detect

    assert_empty bug_anomalies
  end
end
