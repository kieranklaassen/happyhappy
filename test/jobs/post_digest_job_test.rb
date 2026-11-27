require "test_helper"

class PostDigestJobTest < ActiveJob::TestCase
  include SlackStubHelper

  test "posts the previous day's digest to the product channel, records timestamps, and clears last_error" do
    stub_slack_post_message
    digest = DailyDigest.create!(product: products(:cora), date: Date.new(2030, 1, 15), last_error: "Slack HTTP 503")

    freeze_time do
      PostDigestJob.perform_now(digest)

      post = slack_posts.sole
      assert_equal "C0CORASUPPORT", post["channel"]
      assert_equal "Cora digest for January 14, 2030", post["text"]
      assert_includes post["blocks"].to_json, "Quiet day: no new feedback about Cora."

      digest.reload
      assert_predicate digest, :posted?
      assert_equal SLACK_OK_TS, digest.slack_message_ts
      assert_equal Time.current, digest.posted_at
      assert_nil digest.last_error
    end
  end

  test "does nothing when the digest is already posted" do
    stub_slack_post_message
    digest = DailyDigest.create!(product: products(:cora), date: Date.new(2030, 1, 15),
      posted_at: Time.current, slack_message_ts: "1727100000.000500")

    PostDigestJob.perform_now(digest)

    assert_empty slack_posts
    assert_equal "1727100000.000500", digest.reload.slack_message_ts
  end

  test "records last_error and re-raises a permanent Slack error without retrying" do
    stub_slack_post_message("chat_post_message_channel_not_found")
    digest = DailyDigest.create!(product: products(:cora), date: Date.new(2030, 1, 15))

    assert_no_enqueued_jobs(only: PostDigestJob) do
      error = assert_raises(Slack::Client::Error) { PostDigestJob.perform_now(digest) }
      assert_equal "channel_not_found", error.code
    end

    digest.reload
    assert_equal "Slack: channel_not_found", digest.last_error
    assert_not digest.posted?
    assert_nil digest.slack_message_ts
  end

  test "records last_error and retries on a retryable Slack error, then posts once Slack recovers" do
    stub_slack_post_message("chat_post_message_ratelimited")
    digest = DailyDigest.create!(product: products(:cora), date: Date.new(2030, 1, 15))

    assert_enqueued_with(job: PostDigestJob, args: [ digest ]) do
      PostDigestJob.perform_now(digest)
    end

    digest.reload
    assert_equal "Slack: ratelimited", digest.last_error
    assert_not digest.posted?

    stub_slack_post_message
    perform_enqueued_jobs(only: PostDigestJob)

    digest.reload
    assert_predicate digest, :posted?
    assert_equal SLACK_OK_TS, digest.slack_message_ts
    assert_nil digest.last_error
  end

  test "re-raises RetryableError after exhausting retry attempts" do
    stub_slack_post_message(status: 503, body: "upstream error")
    digest = DailyDigest.create!(product: products(:cora), date: Date.new(2030, 1, 15))

    PostDigestJob.perform_later(digest)
    assert_raises(Slack::Client::RetryableError) do
      10.times { perform_enqueued_jobs(only: PostDigestJob) }
    end

    assert_equal 10, slack_posts.size
    assert_equal "Slack HTTP 503", digest.reload.last_error
    assert_not digest.posted?
  end
end
