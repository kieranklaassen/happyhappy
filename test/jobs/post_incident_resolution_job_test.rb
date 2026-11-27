require "test_helper"

class PostIncidentResolutionJobTest < ActiveJob::TestCase
  include AnomalyHelper
  include SlackStubHelper

  setup do
    @incident = Incident.for_anomaly!(create_anomaly!)
    @incident.update!(slack_channel_id: "C0AGCDCD6KG", slack_message_ts: SLACK_OK_TS)
  end

  test "does nothing when the incident is still open" do
    PostIncidentResolutionJob.perform_now(@incident)

    assert_empty slack_calls
  end

  test "does nothing when the incident was not posted to Slack" do
    resolve_incident!(slack_channel_id: nil, slack_message_ts: nil)

    PostIncidentResolutionJob.perform_now(@incident)

    assert_empty slack_calls
  end

  test "does nothing when Slack channel or message timestamp is missing" do
    resolve_incident!(slack_message_ts: nil)
    PostIncidentResolutionJob.perform_now(@incident)

    resolve_incident!(slack_channel_id: nil, slack_message_ts: SLACK_OK_TS)
    PostIncidentResolutionJob.perform_now(@incident)

    assert_empty slack_calls
  end

  test "reloads a stale incident, updates the original ping, and posts a threaded reply" do
    stale = Incident.find(@incident.id)
    resolve_incident!(resolved_by_name: "Ana Every", resolution_note: "Fixed the IMAP sync")
    stub_resolution_slack

    PostIncidentResolutionJob.perform_now(stale)

    assert_equal %w[chat.update chat.postMessage], slack_calls.map(&:first)

    update = slack_calls_to("chat.update").sole
    assert_equal "C0AGCDCD6KG", update["channel"]
    assert_equal SLACK_OK_TS, update["ts"]
    assert_equal "Resolved: Cora incident (bug messages spiked)", update["text"]
    assert_includes update["blocks"].to_json, "Resolved* by Ana Every: Fixed the IMAP sync"
    assert_not_includes update["blocks"].to_json, "Mark resolved"

    reply = slack_calls_to("chat.postMessage").sole
    assert_equal "C0AGCDCD6KG", reply["channel"]
    assert_equal SLACK_OK_TS, reply["thread_ts"]
    assert_equal ":white_check_mark: Resolved by Ana Every: Fixed the IMAP sync", reply["text"]
  end

  test "falls back to someone when resolved_by_name is nil and omits blank notes" do
    resolve_incident!(resolved_by_name: nil, resolution_note: "   ", items_handled: false)
    stub_resolution_slack

    PostIncidentResolutionJob.perform_now(@incident)

    assert_equal ":white_check_mark: Resolved by someone", slack_calls_to("chat.postMessage").sole["text"]
  end

  test "escapes mrkdwn and channel mentions in resolver name and note and truncates long notes" do
    long_note = "<tag> & @channel " + ("a" * 500)
    resolve_incident!(resolved_by_name: "Ana <ops> & @here", resolution_note: long_note)
    stub_resolution_slack

    PostIncidentResolutionJob.perform_now(@incident)

    expected_note = "&lt;tag&gt; &amp; @\u200Bchannel " + ("a" * 480) + "..."
    assert_equal ":white_check_mark: Resolved by Ana &lt;ops&gt; &amp; @\u200Bhere: #{expected_note}",
      slack_calls_to("chat.postMessage").sole["text"]
  end

  test "appends driving items suffix when items_handled is true" do
    resolve_incident!(resolved_by_name: "Ana Every", resolution_note: nil, items_handled: true)
    stub_resolution_slack

    PostIncidentResolutionJob.perform_now(@incident)

    assert_equal ":white_check_mark: Resolved by Ana Every (driving items marked handled)",
      slack_calls_to("chat.postMessage").sole["text"]
  end

  test "includes both resolution note and driving items suffix when both are set" do
    resolve_incident!(resolved_by_name: "Ana Every", resolution_note: "Fixed sync", items_handled: true)
    stub_resolution_slack

    PostIncidentResolutionJob.perform_now(@incident)

    assert_equal ":white_check_mark: Resolved by Ana Every: Fixed sync (driving items marked handled)",
      slack_calls_to("chat.postMessage").sole["text"]
  end

  test "retries on a retryable Slack error without posting the thread reply" do
    resolve_incident!
    stub_slack_method("chat.update", { ok: false, error: "ratelimited" })

    assert_enqueued_with(job: PostIncidentResolutionJob, args: [ @incident ]) do
      PostIncidentResolutionJob.perform_now(@incident)
    end

    assert_empty slack_calls_to("chat.postMessage")
  end

  test "re-raises permanent Slack errors without retrying" do
    resolve_incident!
    stub_slack_method("chat.update", { ok: false, error: "channel_not_found" })

    assert_no_enqueued_jobs(only: PostIncidentResolutionJob) do
      error = assert_raises(Slack::Client::Error) { PostIncidentResolutionJob.perform_now(@incident) }
      assert_equal "channel_not_found", error.code
    end

    assert_empty slack_calls_to("chat.postMessage")
  end

  private

  def resolve_incident!(**attributes)
    @incident.update!({ status: :resolved, resolved_at: Time.current, resolved_by_name: "Ana Every" }.merge(attributes))
  end

  def stub_resolution_slack
    stub_slack_method("chat.update")
    stub_slack_method("chat.postMessage", { ok: true, ts: "1727200001.000100" })
  end
end
