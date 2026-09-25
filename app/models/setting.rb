class Setting < ApplicationRecord
  validates :low_confidence_threshold, :escalation_threshold,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :report_back_window_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :anomaly_sensitivity, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  validates :anomaly_min_count, :anomaly_min_baseline_windows, :anomaly_active_days,
    numericality: { only_integer: true, greater_than: 0 }

  def self.current
    first || create!
  end

  def report_back_window
    report_back_window_minutes.minutes
  end
end
