# Stubs Slack chat.postMessage with recorded response bodies from
# test/fixtures/files/slack/ so no test reaches Slack. Including it also sets
# SLACK_BOT_TOKEN to a test value for each test.
#
#   include SlackStubHelper
#   stub_slack_post_message                                         # ok, ts SLACK_OK_TS
#   stub_slack_post_message("chat_post_message_channel_not_found")  # ok: false
#   stub_slack_post_message(status: 503, body: "upstream error")
#   slack_posts # => parsed JSON bodies of every stubbed request, oldest first
module SlackStubHelper
  extend ActiveSupport::Concern

  SLACK_POST_MESSAGE_URL = "https://slack.com/api/chat.postMessage".freeze
  SLACK_TEST_TOKEN = "xoxb-test-token".freeze
  SLACK_OK_TS = "1727200000.123456".freeze

  included do
    setup do
      @previous_slack_bot_token = ENV["SLACK_BOT_TOKEN"]
      ENV["SLACK_BOT_TOKEN"] = SLACK_TEST_TOKEN
    end

    teardown { ENV["SLACK_BOT_TOKEN"] = @previous_slack_bot_token }
  end

  def stub_slack_post_message(fixture = "chat_post_message_ok", status: 200, body: nil)
    body ||= file_fixture("slack/#{fixture}.json").read
    stub_request(:post, SLACK_POST_MESSAGE_URL)
      .with(headers: { "Authorization" => "Bearer #{SLACK_TEST_TOKEN}" })
      .to_return do |request|
        slack_posts << JSON.parse(request.body)
        { status: status, body: body, headers: { "Content-Type" => "application/json" } }
      end
  end

  def slack_posts
    @slack_posts ||= []
  end
end
