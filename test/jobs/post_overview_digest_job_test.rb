require "test_helper"

class PostOverviewDigestJobTest < ActiveJob::TestCase
  include SlackStubHelper

  setup { Setting.current.update!(slack_channel_id: "C0AGB2RKA6R", digest_time_zone: "America/Los_Angeles") }

  test "posts the previous day's overview to the Settings channel and marks it posted" do
    stub_slack_post_message
    digest = OverviewDigest.create!(date: Date.new(2030, 1, 15))

    PostOverviewDigestJob.perform_now(digest)

    post = slack_posts.sole
    assert_equal "C0AGB2RKA6R", post["channel"]
    assert_equal "happyhappy daily overview for January 14, 2030", post["text"]
    assert digest.reload.posted?
    assert_equal SlackStubHelper::SLACK_OK_TS, digest.slack_message_ts
  end

  test "a posted overview is never posted twice" do
    stub_slack_post_message
    digest = OverviewDigest.create!(date: Date.new(2030, 1, 15), posted_at: Time.current)

    PostOverviewDigestJob.perform_now(digest)

    assert_empty slack_posts
  end

  test "does nothing once the Settings channel is removed" do
    stub_slack_post_message
    Setting.current.update!(slack_channel_id: nil)
    digest = OverviewDigest.create!(date: Date.new(2030, 1, 15))

    PostOverviewDigestJob.perform_now(digest)

    assert_empty slack_posts
    assert_not digest.reload.posted?
  end

  test "a Slack refusal is kept on the digest" do
    stub_slack_post_message("chat_post_message_channel_not_found")
    digest = OverviewDigest.create!(date: Date.new(2030, 1, 15))

    assert_raises(Slack::Client::Error) { PostOverviewDigestJob.perform_now(digest) }

    assert_equal "Slack: channel_not_found", digest.reload.last_error
    assert_not digest.posted?
  end
end
