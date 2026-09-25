require "test_helper"

class Slack::ClientTest < ActiveSupport::TestCase
  include SlackStubHelper

  BLOCKS = [ { type: "section", text: { type: "mrkdwn", text: "hi" } } ].freeze

  test "posts JSON with the bot token and returns the message ts" do
    stub_slack_post_message

    ts = Slack::Client.new.post_message(channel: "C0CORASUPPORT", text: "hi", blocks: BLOCKS)

    assert_equal SLACK_OK_TS, ts
    assert_equal({ "channel" => "C0CORASUPPORT", "text" => "hi", "blocks" => BLOCKS.as_json }, slack_posts.sole)
  end

  test "Slack 5xx, HTTP 429, and ratelimited are retryable" do
    [ { status: 503, body: "upstream error" }, { status: 429, body: "" } ].each do |response|
      stub_slack_post_message(**response)
      assert_raises(Slack::Client::RetryableError) { post }
    end

    stub_slack_post_message("chat_post_message_ratelimited")
    assert_raises(Slack::Client::RetryableError, match: /ratelimited/) { post }
  end

  test "a network timeout is retryable" do
    stub_request(:post, SLACK_POST_MESSAGE_URL).to_timeout

    assert_raises(Slack::Client::RetryableError) { post }
  end

  test "an API error such as channel_not_found is not retryable" do
    stub_slack_post_message("chat_post_message_channel_not_found")

    error = assert_raises(Slack::Client::Error) { post }
    assert_not_kind_of Slack::Client::RetryableError, error
    assert_equal "Slack: channel_not_found", error.message
  end

  test "a missing token fails without calling Slack" do
    error = assert_raises(Slack::Client::Error) do
      Slack::Client.new(token: nil).post_message(channel: "C1", text: "hi", blocks: BLOCKS)
    end

    assert_equal "SLACK_BOT_TOKEN is not set", error.message
    assert_not_requested :post, SLACK_POST_MESSAGE_URL
  end

  private

  def post
    Slack::Client.new.post_message(channel: "C0CORASUPPORT", text: "hi", blocks: BLOCKS)
  end
end
