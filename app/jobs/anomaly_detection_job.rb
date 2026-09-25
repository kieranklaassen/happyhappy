# Runs Anomalies::Detect for one granularity: "hour" every 15 minutes and "day" once a day,
# from config/recurring.yml.
class AnomalyDetectionJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(granularity) { "anomaly_detection_#{granularity}" }, duration: 15.minutes,
    on_conflict: :discard

  def perform(granularity)
    Anomalies::Detect.call(granularity: granularity)
  end
end
