require "test_helper"

class SyncIncidentSlackJobTest < ActiveJob::TestCase
  include AnomalyHelper
  include SlackStubHelper

  setup do
    products(:cora).update!(alert_channel_id: "C0AGCDCD6KG")
    @incident = Incident.for_anomaly!(create_anomaly!)
  end

  test "joins the channel and retries once when the bot is not in it" do
    stub_slack_method("chat.postMessage", { ok: false, error: "not_in_channel" }, { ok: true, ts: SLACK_OK_TS })
    stub_slack_method("conversations.join", { ok: true, channel: { id: "C0AGCDCD6KG" } })

    SyncIncidentSlackJob.perform_now(@incident)

    assert_equal %w[chat.postMessage conversations.join chat.postMessage], slack_calls.map(&:first)
    assert_equal "C0AGCDCD6KG", slack_calls_to("conversations.join").sole["channel"]
    assert_equal SLACK_OK_TS, @incident.reload.slack_message_ts
  end

  test "a second not_in_channel after joining is an error, not a loop" do
    stub_slack_method("chat.postMessage", { ok: false, error: "not_in_channel" })
    stub_slack_method("conversations.join")

    error = assert_raises(Slack::Client::Error) { SyncIncidentSlackJob.perform_now(@incident) }

    assert_equal "not_in_channel", error.code
    assert_equal 2, slack_calls_to("chat.postMessage").size
    assert_not @incident.reload.slack_posted?
  end

  test "other Slack errors do not join" do
    stub_slack_method("chat.postMessage", { ok: false, error: "channel_not_found" })

    assert_raises(Slack::Client::Error) { SyncIncidentSlackJob.perform_now(@incident) }
    assert_empty slack_calls_to("conversations.join")
  end

  test "an incident resolved before its first post never pings" do
    @incident.update!(status: :resolved, resolved_at: Time.current)

    SyncIncidentSlackJob.perform_now(@incident)

    assert_empty slack_calls
  end
end
