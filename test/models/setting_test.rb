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

  test "the daily overview defaults to 8:00 in Los Angeles with no Slack channel" do
    Setting.delete_all
    setting = Setting.current

    assert_nil setting.slack_channel_id
    assert_not setting.slack_channel?
    assert_equal 8, setting.digest_hour
    assert_equal ActiveSupport::TimeZone["America/Los_Angeles"], setting.digest_zone
  end

  test "a blank Slack channel is stored as none" do
    settings(:current).update!(slack_channel_id: "  ")

    assert_nil settings(:current).reload.slack_channel_id
  end

  test "team lists default to the every.to domain and accept comma- or space-separated strings" do
    Setting.delete_all
    setting = Setting.current
    assert_equal [ "every.to" ], setting.team_email_domains

    setting.update!(team_email_domains: " Every.to, @cora.computer every.to", team_discord_role_ids: "797, 789 ",
      team_discord_user_ids: [ " 42 ", "" ])

    assert_equal %w[every.to cora.computer], setting.reload.team_email_domains
    assert_equal %w[797 789], setting.team_discord_role_ids
    assert_equal %w[42], setting.team_discord_user_ids
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
