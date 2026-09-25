require "test_helper"

class AnomalyDetectionJobTest < ActiveJob::TestCase
  include AnomalyHelper

  test "runs detection for the given granularity" do
    now = anomaly_now
    steady_series!(ending: now - 1.hour, step: 1.hour, windows: 12)
    8.times { |index| customer_message!(at: now - 1.hour + (index + 1).minutes) }

    travel_to(now) { AnomalyDetectionJob.perform_now("hour") }

    assert DetectedAnomaly.exists?(product: products(:cora), source: nil, metric: "volume", granularity: "hour")
  end

  test "the daily pass runs without data" do
    assert_nothing_raised { AnomalyDetectionJob.perform_now("day") }
    assert_empty DetectedAnomaly.all
  end
end
