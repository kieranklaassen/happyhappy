require "test_helper"

class Webhooks::SlackControllerTest < ActionDispatch::IntegrationTest
  include SlackEventsHelper

  setup do
    stub_slack_users_info
    stub_slack_permalink
  end

  test "a signed message event in a configured channel creates an item" do
    assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      perform_enqueued_jobs(only: SlackEventJob) do
        post_event slack_payload("message_event")
      end
    end

    assert_response :ok
    item = Item.find_by!(source_kind: "slack", thread_key: "C0COMMUNITY:1727200000.000200")
    assert_equal "mara.writes", item.author_handle
    assert_equal "https://every-community.slack.com/archives/C0COMMUNITY/p1727200000000200", item.permalink
  end

  test "a thread reply attaches to the parent message's item" do
    perform_enqueued_jobs(only: SlackEventJob) do
      post_event slack_payload("message_event")
      post_event slack_payload("thread_reply_event")
    end

    item = Item.find_by!(source_kind: "slack", thread_key: "C0COMMUNITY:1727200000.000200")
    assert_equal 2, item.messages.count
  end

  test "a bad signature returns 401 and stores nothing" do
    body = slack_payload("message_event").to_json

    assert_no_enqueued_jobs do
      with_slack_env do
        post webhooks_slack_events_path, params: body, headers: slack_signature_headers(body, secret: "wrong-secret")
      end
    end

    assert_response :unauthorized
  end

  test "a missing signature returns 401" do
    body = slack_payload("message_event").to_json

    with_slack_env do
      post webhooks_slack_events_path, params: body, headers: { "Content-Type" => "application/json" }
    end

    assert_response :unauthorized
  end

  test "a stale timestamp returns 401" do
    body = slack_payload("message_event").to_json

    assert_no_enqueued_jobs do
      with_slack_env do
        post webhooks_slack_events_path, params: body,
          headers: slack_signature_headers(body, timestamp: 6.minutes.ago.to_i)
      end
    end

    assert_response :unauthorized
  end

  test "a blank signing secret rejects every request" do
    body = slack_payload("message_event").to_json

    with_slack_env(signing_secret: "") do
      post webhooks_slack_events_path, params: body, headers: slack_signature_headers(body, secret: "")
    end

    assert_response :unauthorized
  end

  test "url_verification returns the challenge" do
    post_event slack_payload("url_verification")

    assert_response :ok
    assert_equal "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P", response.parsed_body["challenge"]
  end

  test "a message in an unconfigured channel returns 200 and stores nothing" do
    assert_no_enqueued_jobs do
      post_event slack_payload("message_event", event: { channel: "C0UNKNOWN" })
    end

    assert_response :ok
  end

  test "a retried event with X-Slack-Retry-Num stores one message" do
    payload = slack_payload("message_event")

    assert_difference -> { Message.count } => 1 do
      perform_enqueued_jobs(only: SlackEventJob) do
        post_event payload
        post_event payload, headers: { "X-Slack-Retry-Num" => "1", "X-Slack-Retry-Reason" => "http_timeout" }
      end
    end

    assert_response :ok
  end

  test "a bot message is ignored" do
    assert_no_enqueued_jobs do
      post_event slack_payload("bot_message_event")
    end

    assert_response :ok
  end

  test "a message edit is ignored" do
    assert_no_enqueued_jobs do
      post_event slack_payload("message_changed_event")
    end

    assert_response :ok
  end

  test "a signed body that is not JSON returns 400" do
    with_slack_env do
      post webhooks_slack_events_path, params: "not json", headers: slack_signature_headers("not json")
    end

    assert_response :bad_request
  end

  test "answers before any Slack lookup or classification and leaves both to the realtime queue" do
    fake = use_fake_classifier

    assert_no_difference -> { Message.count } do
      assert_enqueued_with(job: SlackEventJob, queue: "realtime") { post_event slack_payload("message_event") }
    end

    assert_response :ok
    assert_empty fake.calls
    assert_not_requested :post, %r{slack.com/api}
  end

  private

  def post_event(payload, headers: {})
    body = payload.to_json
    with_slack_env do
      post webhooks_slack_events_path, params: body, headers: slack_signature_headers(body).merge(headers)
    end
  end
end
