require "test_helper"

# Webhook deliveries carry customer message content as request parameters; the
# request log must show them filtered.
class WebhookLogFilteringTest < ActionDispatch::IntegrationTest
  include SlackEventsHelper
  include IntercomPayloads

  test "Postmark, Intercom, and Slack message content is filtered from the request log" do
    postmark = JSON.parse(file_fixture("postmark/inbound_first.json").read)
    intercom = intercom_created
    slack = slack_payload("message_event")

    log = capture_request_log do
      post postmark_webhook_path, params: postmark.to_json, headers: { "Content-Type" => "application/json" }
      post "/webhooks/intercom", params: intercom.to_json, headers: { "Content-Type" => "application/json" }
      post webhooks_slack_events_path, params: slack.to_json, headers: { "Content-Type" => "application/json" }
    end

    assert_includes log, "Parameters:"
    assert_includes log, "[FILTERED]"
    [
      postmark["TextBody"].lines.first.strip, postmark["Subject"], postmark.dig("Attachments", 0, "Content")[0, 20],
      "Cora stopped sorting my inbox this morning", slack.dig("event", "text")
    ].each { |content| assert_not_includes log, content }
  end

  test "Slack event jobs do not log their envelope" do
    assert_not SlackEventJob.log_arguments?
  end

  private

  def capture_request_log
    io = StringIO.new
    previous = ActionController::Base.logger
    ActionController::Base.logger = ActiveSupport::Logger.new(io, level: :info)
    yield
    io.string
  ensure
    ActionController::Base.logger = previous
  end
end
