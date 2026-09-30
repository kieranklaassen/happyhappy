require "test_helper"

class Incidents::CorrelateTest < ActiveJob::TestCase
  include AnomalyHelper
  include SlackStubHelper

  setup do
    products(:cora).update!(alert_channel_id: "C0AGCDCD6KG", alert_mention_ids: %w[U0AGQDHRV8U S0BINGSU01])
    stub_slack_method("chat.postMessage", { ok: true, ts: SLACK_OK_TS })
    stub_slack_method("chat.update")
  end

  def correlate(anomaly)
    perform_enqueued_jobs(only: SyncIncidentSlackJob) { Incidents::Correlate.call(anomaly) }
  end

  test "a new negative anomaly opens an incident and pings the product's own alert channel once, mentioning on-call" do
    anomaly = create_anomaly!

    incident = correlate(anomaly)

    assert_predicate incident, :open?
    assert_equal products(:cora), incident.product
    assert_equal incident, anomaly.reload.incident
    post = slack_calls_to("chat.postMessage").sole
    assert_equal "C0AGCDCD6KG", post["channel"]
    assert_includes post["text"], "<@U0AGQDHRV8U> <!subteam^S0BINGSU01>"
    assert_includes post["blocks"].first.dig("text", "text"), "<@U0AGQDHRV8U> <!subteam^S0BINGSU01>"
    assert_equal [ "C0AGCDCD6KG", SLACK_OK_TS ], incident.reload.values_at(:slack_channel_id, :slack_message_ts)
    assert_not_equal "C0CORASUPPORT", post["channel"], "the product's escalation channel is not its alert channel"
  end

  test "negative anomalies on other sources and metrics within the window join the incident and update the ping" do
    first = create_anomaly!
    incident = correlate(first)

    travel 30.minutes do
      second = create_anomaly!(source: sources(:intercom_inbox), metric: "volume", dimension: nil)
      third = create_anomaly!(source: sources(:discord_spiral), metric: "complaint_share", dimension: nil, expected: 0.2, actual: 0.7)
      assert_equal incident, correlate(second)
      assert_equal incident, correlate(third)
    end

    assert_equal 1, Incident.count
    assert_equal 3, incident.anomalies.count
    assert_equal 1, slack_calls_to("chat.postMessage").size
    updates = slack_calls_to("chat.update")
    assert_equal 2, updates.size
    assert_equal [ "C0AGCDCD6KG", SLACK_OK_TS ], updates.last.values_at("channel", "ts")
    rendered = updates.last["blocks"].to_json
    assert_includes rendered, "Discord"
    assert_includes rendered, "Intercom"
  end

  test "a negative anomaly after the window opens a new incident and a new ping" do
    correlate(create_anomaly!)

    travel 3.hours do
      correlate(create_anomaly!)
    end

    assert_equal 2, Incident.count
    assert_equal 2, slack_calls_to("chat.postMessage").size
  end

  test "the window comes from Settings" do
    Setting.current.update!(incident_window_minutes: 240)
    incident = correlate(create_anomaly!)

    travel 3.hours do
      assert_equal incident, correlate(create_anomaly!)
    end
  end

  test "good news, neutral news, history, and other products never join an incident" do
    positive = create_anomaly!(polarity: "positive", severity: nil, highlight: "big", metric: "mood_share", dimension: "beaming")
    neutral = create_anomaly!(polarity: "neutral", severity: nil, metric: "volume", dimension: nil)
    history = create_anomaly!(historical: true, status: "ended", ended_at: Time.current)

    [ positive, neutral, history ].each { |anomaly| assert_nil correlate(anomaly) }
    incident = correlate(create_anomaly!)
    other = correlate(create_anomaly!(product: products(:sparkle)))

    assert_not_equal incident, other
    assert_empty slack_calls_to("chat.postMessage").select { |post| post["channel"] != "C0AGCDCD6KG" }
  end

  test "the same spike seen at the other granularity after it was resolved joins the resolved incident silently" do
    hourly = create_anomaly!
    incident = correlate(hourly)
    Incidents::Resolve.call(incident: incident, actor_name: "Ana")
    slack_calls.clear

    daily = create_anomaly!(granularity: "day", window_start: Time.current.beginning_of_day, window_end: Time.current.end_of_day)
    other_series = create_anomaly!(granularity: "day", metric: "volume", dimension: nil,
      window_start: Time.current.beginning_of_day, window_end: Time.current.end_of_day)

    assert_nil correlate(daily)
    daily.reload
    assert_equal incident, daily.incident
    assert_predicate daily, :ended?
    assert_predicate daily, :resolved?
    assert_not_equal incident, correlate(other_series), "a different series is new bad news"
    assert_equal 1, slack_calls_to("chat.postMessage").size
  end

  test "a product without an alert channel still gets an incident, with no ping" do
    products(:cora).update!(alert_channel_id: nil)

    incident = correlate(create_anomaly!)

    assert_predicate incident, :open?
    assert_not incident.slack_posted?
    assert_empty slack_calls
  end
end
