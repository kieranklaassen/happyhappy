# Builds deterministic message series for anomaly detection tests. Detection runs a year ahead so
# the fixture messages (all within the last few weeks) never fall inside its lookback.
#
#   now = anomaly_now
#   customer_message!(at: now - 3.hours, category: categories(:bug))
#   Anomalies::Detect.call(granularity: "hour", now: now)
module AnomalyHelper
  def anomaly_now
    @anomaly_now ||= 1.year.from_now.beginning_of_hour
  end

  def customer_message!(at:, product: products(:cora), source: sources(:slack_community), sentiment: "question",
                        anger: 0.1, category: nil, author: nil, backfilled: false, classified: true, **message)
    item = Item.create!(source: source, thread_key: "anomaly-#{SecureRandom.hex(6)}", product: product,
      category: category, sentiment: sentiment, sentiment_probability: 0.9,
      author_handle: author || "customer_#{SecureRandom.hex(4)}", last_message_at: at, relevant: true)
    item.messages.create!(source: source, external_id: SecureRandom.uuid, body: "About #{product.name}",
      occurred_at: at, anger_probability: anger, classified_at: (at if classified), backfilled: backfilled, **message)
  end

  def create_anomaly!(**attributes)
    now = Time.current
    DetectedAnomaly.create!({
      product: products(:cora), metric: "category_volume", dimension: categories(:bug).id.to_s, granularity: "hour",
      window_start: now - 1.hour, window_end: now, expected: 0.4, actual: 9, z_score: 12,
      polarity: "negative", severity: "high",
      item_ids: [ items(:angry_slack).id ], first_seen_at: now, last_seen_at: now
    }.merge(attributes))
  end

  # A steady baseline: `per_window` messages in each of the `windows` windows before `ending`.
  def steady_series!(ending:, step:, windows:, per_window: [ 1, 2, 1, 2 ], **attributes)
    windows.times do |back|
      window_start = ending - (back + 1) * step
      per_window[back % per_window.size].times do |index|
        customer_message!(at: window_start + (index + 1).minutes, **attributes)
      end
    end
  end
end
