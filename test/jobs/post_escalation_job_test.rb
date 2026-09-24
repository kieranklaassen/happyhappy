require "test_helper"

class PostEscalationJobTest < ActiveJob::TestCase
  include SlackStubHelper

  setup do
    @escalation = items(:angry_slack).escalations.create!(product: products(:cora),
      slack_channel_id: "C0CORASUPPORT", message: messages(:angry_slack_first))
  end

  test "posts to the product channel, stores the ts, and writes an escalated event" do
    stub_slack_post_message

    PostEscalationJob.perform_now(@escalation)

    @escalation.reload
    assert @escalation.posted?
    assert_equal SLACK_OK_TS, @escalation.slack_message_ts
    assert_nil @escalation.last_error
    assert_equal "C0CORASUPPORT", slack_posts.sole["channel"]

    event = items(:angry_slack).events.where(kind: "escalated").sole
    assert_equal({ "escalation_id" => @escalation.id, "slack_channel_id" => "C0CORASUPPORT",
      "slack_message_ts" => SLACK_OK_TS }, event.data)
  end

  test "a Slack 5xx records the error, keeps the escalation, and retries" do
    stub_slack_post_message(status: 503, body: "upstream error")

    assert_enqueued_with(job: PostEscalationJob, args: [ @escalation ]) do
      PostEscalationJob.perform_now(@escalation)
    end

    @escalation.reload
    assert_not @escalation.posted?
    assert_equal "Slack HTTP 503", @escalation.last_error
    assert_not items(:angry_slack).events.where(kind: "escalated").exists?
  end

  test "the retry after a 5xx posts once Slack recovers" do
    stub_slack_post_message(status: 503, body: "upstream error")
    PostEscalationJob.perform_now(@escalation)

    stub_slack_post_message
    perform_enqueued_jobs

    @escalation.reload
    assert @escalation.posted?
    assert_nil @escalation.last_error
  end

  test "a permanent Slack error records the error and fails the job without dropping the record" do
    stub_slack_post_message("chat_post_message_channel_not_found")

    assert_raises(Slack::Client::Error) { PostEscalationJob.perform_now(@escalation) }

    assert_equal "Slack: channel_not_found", @escalation.reload.last_error
    assert_not @escalation.posted?
  end

  test "an already posted escalation is not posted again" do
    PostEscalationJob.perform_now(escalations(:angry_slack_posted))

    assert_not_requested :post, SLACK_POST_MESSAGE_URL
  end
end
