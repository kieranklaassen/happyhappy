require "test_helper"

class Connectors::SlackTest < ActiveSupport::TestCase
  include SlackEventsHelper

  setup do
    @users_info = stub_slack_users_info
    @permalink = stub_slack_permalink
    @connector = Connectors::Slack.new(client: Slack::Web::Client.new(token: "xoxb-test-token"))
  end

  test "maps a channel message to an item with author and permalink" do
    result = assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      @connector.ingest(slack_payload("message_event"))
    end

    item = result.item
    assert_equal sources(:slack_community), item.source
    assert_equal "slack", item.source_kind
    assert_equal "C0COMMUNITY:1727200000.000200", item.thread_key
    assert_equal "mara.writes", item.author_handle
    assert_equal "Mara", item.author_name
    assert_equal "mara@example.com", item.author_email
    assert_equal "https://every-community.slack.com/archives/C0COMMUNITY/p1727200000000200", item.permalink
    assert_equal products(:cora), item.product

    message = result.message
    assert_equal "C0COMMUNITY:1727200000.000200", message.external_id
    assert_match "cannot find the undo", message.body
    assert_equal Time.zone.at(1727200000.0002r), message.occurred_at
    assert_equal "U0CUSTOMER", message.raw_payload["user"]
  end

  test "a thread reply attaches to the parent message's item" do
    parent = @connector.ingest(slack_payload("message_event")).item

    reply = assert_no_difference -> { Item.count } do
      assert_difference -> { parent.messages.count } => 1 do
        @connector.ingest(slack_payload("thread_reply_event"))
      end
    end

    assert_equal parent, reply.item
    assert_equal "C0COMMUNITY:1727200900.000300", reply.message.external_id
    assert_equal parent.permalink, reply.item.reload.permalink
  end

  test "a thread broadcast is ingested onto its thread" do
    parent = @connector.ingest(slack_payload("message_event")).item

    result = @connector.ingest(slack_payload("thread_reply_event", event: { subtype: "thread_broadcast" }))

    assert_equal parent, result.item
  end

  test "a message with a file attached is ingested" do
    result = @connector.ingest(slack_payload("message_event", event: { subtype: "file_share", text: "" }))

    assert_equal "", result.message.body
  end

  test "the same ts in two configured channels creates two items" do
    first = @connector.ingest(slack_payload("message_event"))
    second = @connector.ingest(slack_payload("message_event", event: { channel: "C0LEXLEGACY" }))

    assert_not_equal first.item, second.item
    assert_equal sources(:lex_legacy), second.item.source
    assert_equal "C0LEXLEGACY:1727200000.000200", second.item.thread_key
  end

  test "a redelivered message is stored once and skips the Slack lookups" do
    @connector.ingest(slack_payload("message_event"))

    result = assert_no_difference -> { Message.count } do
      @connector.ingest(slack_payload("message_event"))
    end

    assert result.duplicate?
    assert_requested @users_info, times: 1
    assert_requested @permalink, times: 1
  end

  test "users.info lookups are cached per user" do
    connector = Connectors::Slack.new(client: Slack::Web::Client.new(token: "xoxb-test-token"),
      cache: ActiveSupport::Cache::MemoryStore.new)

    connector.ingest(slack_payload("message_event"))
    connector.ingest(slack_payload("thread_reply_event"))

    assert_requested @users_info, times: 1
    assert_requested @permalink, times: 2
  end

  test "a failed users.info lookup still ingests and records the source error" do
    stub_slack_error("users.info", "missing_scope")

    item = @connector.ingest(slack_payload("message_event")).item

    assert_equal "U0CUSTOMER", item.author_handle
    assert_nil item.author_name
    assert_match "missing_scope", sources(:slack_community).reload.last_error
  end

  test "a failed permalink lookup falls back to the archive link" do
    stub_slack_error("chat.getPermalink", "message_not_found")

    item = @connector.ingest(slack_payload("message_event")).item

    assert_equal "https://slack.com/archives/C0COMMUNITY/p1727200000000200", item.permalink
    assert_match "message_not_found", sources(:slack_community).reload.last_error
  end

  test "a Slack outage during lookups still ingests the message" do
    stub_request(:post, "#{SlackEventsHelper::API}/users.info").to_return(status: 503)

    assert_difference -> { Message.count } => 1 do
      @connector.ingest(slack_payload("message_event"))
    end
  end

  test "ignores messages that are not customer posts in a configured public channel" do
    ignored = {
      "bot message" => slack_payload("bot_message_event"),
      "message edit" => slack_payload("message_changed_event"),
      "message delete" => slack_payload("message_event", event: { subtype: "message_deleted" }),
      "channel join" => slack_payload("message_event", event: { subtype: "channel_join" }),
      "happyhappy's own bot user" => slack_payload("message_event", event: { user: "U0HAPPYBOT" }),
      "app posting as a user" => slack_payload("message_event", event: { bot_id: "B0HAPPYHAPPY" }),
      "private channel" => slack_payload("message_event", event: { channel_type: "group" }),
      "direct message" => slack_payload("message_event", event: { channel_type: "im" }),
      "unconfigured channel" => slack_payload("message_event", event: { channel: "C0UNKNOWN" }),
      "non-message event" => slack_payload("message_event", event: { type: "reaction_added" }),
      "non-callback envelope" => slack_payload("url_verification")
    }

    ignored.each do |label, payload|
      assert_not Connectors::Slack.ingestible?(payload), "#{label} should not be ingestible"
      assert_nil @connector.ingest(payload), "#{label} should not ingest"
    end
    assert_not_requested @users_info
  end

  test "ignores messages for a paused source" do
    sources(:slack_community).update!(status: :paused)

    assert_nil @connector.ingest(slack_payload("message_event"))
  end
end
