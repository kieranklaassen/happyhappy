# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:every_ana) }

  test "show renders the current thresholds" do
    get settings_path

    assert_response :success
    assert_inertia_component "settings/edit"
    assert_inertia_props({ setting: {
      low_confidence_threshold: 0.6, escalation_threshold: 0.8, report_back_window_minutes: 240,
      anomaly_sensitivity: 3.0, anomaly_min_count: 5, anomaly_min_baseline_windows: 6, anomaly_active_days: 7,
      team_email_domains: [ "every.to" ], team_discord_role_ids: [], team_discord_user_ids: [],
      slack_channel_id: nil, digest_time_zone: "America/Los_Angeles", digest_hour: 8
    } })
    assert_includes inertia.props[:time_zones], "America/Los_Angeles"
    assert_includes inertia.props[:time_zones], "Europe/Amsterdam"
  end

  test "update saves the Slack channel and the daily overview time" do
    patch settings_path, params: { setting: {
      slack_channel_id: " C0AGB2RKA6R ", digest_time_zone: "Europe/Amsterdam", digest_hour: "9"
    } }

    assert_redirected_to settings_path
    setting = Setting.current
    assert_equal "C0AGB2RKA6R", setting.slack_channel_id
    assert_equal "Europe/Amsterdam", setting.digest_time_zone
    assert_equal 9, setting.digest_hour
  end

  test "an unknown time zone, an hour of 24, and a channel name instead of an ID are rejected" do
    patch settings_path, params: { setting: { digest_time_zone: "Mars/Olympus", digest_hour: "24", slack_channel_id: "#customer-support" } }

    follow_redirect!
    %w[digest_time_zone digest_hour slack_channel_id].each { |field| assert inertia.props[:errors][field].present?, field }
    assert_equal "America/Los_Angeles", Setting.current.digest_time_zone
  end

  test "update saves new thresholds" do
    patch settings_path, params: { setting: {
      low_confidence_threshold: "0.55", escalation_threshold: "0.9", report_back_window_minutes: "120"
    } }

    assert_redirected_to settings_path
    setting = Setting.current
    assert_equal 0.55, setting.low_confidence_threshold
    assert_equal 0.9, setting.escalation_threshold
    assert_equal 120, setting.report_back_window_minutes
  end

  test "update saves the team lists from comma-separated text" do
    patch settings_path, params: { setting: {
      team_email_domains: "every.to, cora.computer", team_discord_role_ids: "797476545076920320",
      team_discord_user_ids: ""
    } }

    assert_redirected_to settings_path
    setting = Setting.current
    assert_equal %w[every.to cora.computer], setting.team_email_domains
    assert_equal %w[797476545076920320], setting.team_discord_role_ids
    assert_empty setting.team_discord_user_ids
  end

  test "a threshold of 1.5 is rejected" do
    patch settings_path, params: { setting: { escalation_threshold: "1.5" } }

    assert_redirected_to settings_path
    follow_redirect!
    assert inertia.props[:errors]["escalation_threshold"].present?
    assert_equal 0.8, Setting.current.escalation_threshold
  end

  test "a negative low-confidence threshold and a zero report-back window are rejected" do
    patch settings_path, params: { setting: { low_confidence_threshold: "-0.1", report_back_window_minutes: "0" } }

    follow_redirect!
    assert inertia.props[:errors]["low_confidence_threshold"].present?
    assert inertia.props[:errors]["report_back_window_minutes"].present?
  end

  test "update saves anomaly thresholds and rejects a zero minimum count" do
    patch settings_path, params: { setting: { anomaly_sensitivity: "2.5", anomaly_active_days: "3" } }

    assert_equal 2.5, Setting.current.anomaly_sensitivity
    assert_equal 3, Setting.current.anomaly_active_days

    patch settings_path, params: { setting: { anomaly_min_count: "0" } }
    follow_redirect!
    assert inertia.props[:errors]["anomaly_min_count"].present?
    assert_equal 5, Setting.current.anomaly_min_count
  end
end
