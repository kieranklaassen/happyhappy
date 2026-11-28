require "test_helper"

class SlackEventJobTest < ActiveJob::TestCase
  include SlackEventsHelper

  setup do
    stub_slack_users_info
    stub_slack_permalink
  end

  test "runs on the realtime queue and disables argument logging" do
    assert_equal "realtime", SlackEventJob.queue_name
    assert_not SlackEventJob.log_arguments?
  end

  test "enqueues onto the realtime queue with the envelope payload" do
    envelope = slack_payload("message_event")

    assert_enqueued_with(job: SlackEventJob, args: [ envelope ], queue: "realtime") do
      SlackEventJob.perform_later(envelope)
    end
  end

  test "perform ingests a customer message envelope and enqueues classification" do
    envelope = slack_payload("message_event")
    result = nil

    with_slack_env do
      assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
        result = SlackEventJob.perform_now(envelope)
      end
    end

    assert_not result.duplicate?
    assert_equal "C0COMMUNITY:1727200000.000200", result.item.thread_key
    assert_equal "mara.writes", result.item.author_handle
    assert_equal "https://every-community.slack.com/archives/C0COMMUNITY/p1727200000000200", result.item.permalink
    assert_enqueued_with(job: ClassifyMessageJob, args: [ result.message ], queue: "realtime")
  end

  test "perform is idempotent when the same envelope is delivered twice" do
    envelope = slack_payload("message_event")

    with_slack_env do
      first = SlackEventJob.perform_now(envelope)
      clear_enqueued_jobs

      second = nil
      assert_no_difference [ -> { Item.count }, -> { Message.count } ] do
        second = SlackEventJob.perform_now(envelope)
      end

      assert second.duplicate?
      assert_equal first.message, second.message
      assert_no_enqueued_jobs
    end
  end

  test "perform ignores non-ingestible envelopes without calling Slack" do
    with_slack_env do
      assert_no_difference [ -> { Item.count }, -> { Message.count } ] do
        assert_nil SlackEventJob.perform_now(slack_payload("bot_message_event"))
        assert_nil SlackEventJob.perform_now(slack_payload("message_event", event: { channel: "C0UNKNOWN" }))
      end
    end

    assert_not_requested :post, %r{slack.com/api}
    assert_no_enqueued_jobs
  end
end
