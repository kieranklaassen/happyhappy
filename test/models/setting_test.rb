require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "current returns the single settings row" do
    assert_equal settings(:current), Setting.current
    assert_no_difference -> { Setting.count } do
      Setting.current
    end
  end

  test "current creates the row with defaults 0.6, 0.8, and 240 minutes when none exists" do
    Setting.delete_all

    setting = Setting.current

    assert_equal 0.6, setting.low_confidence_threshold
    assert_equal 0.8, setting.escalation_threshold
    assert_equal 240, setting.report_back_window_minutes
    assert_equal 4.hours, setting.report_back_window
    assert_equal 1, Setting.count
  end

  test "rejects probabilities outside 0 to 1" do
    setting = Setting.current
    setting.low_confidence_threshold = 1.5
    setting.escalation_threshold = -0.1

    refute setting.valid?
    assert setting.errors.key?(:low_confidence_threshold)
    assert setting.errors.key?(:escalation_threshold)
  end

  test "rejects a non-positive report-back window" do
    setting = Setting.current
    setting.report_back_window_minutes = 0

    refute setting.valid?
  end
end
