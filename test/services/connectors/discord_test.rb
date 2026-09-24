require "test_helper"

class Connectors::DiscordTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @source = sources(:discord_spiral)
  end

  test "maps a message create payload to an inbound message with a jump link" do
    inbound = Connectors::Discord.inbound_message(payload("message_create"))

    assert_equal "1287654321098765313", inbound.external_id
    assert_equal "1100000000000000001:1287654321098765313", inbound.thread_key
    assert_equal "Spiral keeps losing my draft when I switch tabs. Third time today.", inbound.body
    assert_equal Time.iso8601("2026-09-23T14:05:12.345Z"), inbound.occurred_at
    assert_equal "mayawrites", inbound.author_handle
    assert_equal "Maya", inbound.author_name
    assert_equal "https://discord.com/channels/1000000000000000007/1100000000000000001/1287654321098765313",
      inbound.permalink
    assert_equal payload("message_create"), inbound.raw_payload
    assert inbound.valid?
  end

  test "maps a reply to the replied-to message's thread and keeps attachment links" do
    inbound = Connectors::Discord.inbound_message(payload("message_create_reply"))

    assert_equal "1100000000000000001:1287654321098765313", inbound.thread_key
    assert_equal "tobi.k", inbound.author_name
    assert_equal <<~BODY.chomp, inbound.body
      Same here, and it happened on the desktop app too.
      https://cdn.discordapp.com/attachments/1100000000000000001/1287655445098765314/draft-lost.png
    BODY
  end

  test "skips bot, webhook, system, direct, and empty messages" do
    assert_nil Connectors::Discord.inbound_message(payload("message_create_bot"))
    assert_nil Connectors::Discord.inbound_message(payload("message_create").merge("webhook_id" => "42"))
    assert_nil Connectors::Discord.inbound_message(payload("message_create").merge("type" => 7))
    assert_nil Connectors::Discord.inbound_message(payload("message_create").except("guild_id"))
    assert_nil Connectors::Discord.inbound_message(payload("message_create").merge("content" => "  "))
  end

  test "a message event in a configured channel creates an item with a jump link" do
    result = nil
    assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      result = Connectors::Discord.ingest(payload("message_create"))
    end

    item = result.item
    assert_equal @source, item.source
    assert_equal products(:spiral), item.product
    assert_equal "mayawrites", item.author_handle
    assert_equal "https://discord.com/channels/1000000000000000007/1100000000000000001/1287654321098765313",
      item.permalink
    assert_enqueued_with job: ClassifyMessageJob, args: [ result.message ]
  end

  test "a reply to an earlier message joins that message's item" do
    first = Connectors::Discord.ingest(payload("message_create"))

    reply = nil
    assert_no_difference -> { Item.count } do
      reply = Connectors::Discord.ingest(payload("message_create_reply"))
    end

    assert_equal first.item, reply.item
    assert_equal 2, first.item.messages.count
  end

  test "a reply to a reply joins the root message's item" do
    root = Connectors::Discord.ingest(payload("message_create"))
    Connectors::Discord.ingest(payload("message_create_reply"))

    second_reply = payload("message_create_reply").merge(
      "id" => "1287656000098765313",
      "message_reference" => { "message_id" => "1287655445098765313", "channel_id" => "1100000000000000001" }
    )
    result = Connectors::Discord.ingest(second_reply)

    assert_equal root.item, result.item
  end

  test "a reply to a message happyhappy never stored starts an item keyed on that message" do
    orphan = payload("message_create_reply").merge(
      "message_reference" => { "message_id" => "1287000000000000001", "channel_id" => "1100000000000000001" }
    )

    result = Connectors::Discord.ingest(orphan)

    assert_equal "1100000000000000001:1287000000000000001", result.item.thread_key
  end

  test "a message inside a thread started from a message joins the starter message's item" do
    starter = Connectors::Discord.ingest(payload("message_create"))

    result = Connectors::Discord.ingest(payload("message_create_in_thread"), parent_channel_id: "1100000000000000001")

    assert_equal starter.item, result.item
    assert_equal "https://discord.com/channels/1000000000000000007/1287654321098765313/1287657000098765313",
      Connectors::Discord.inbound_message(payload("message_create_in_thread"), parent_channel_id: "1").permalink
  end

  test "a thread message is ignored when its parent channel is not configured" do
    assert_nil Connectors::Discord.ingest(payload("message_create_in_thread"))
    assert_nil Connectors::Discord.ingest(payload("message_create_in_thread"), parent_channel_id: "1199999999999999999")
  end

  test "bot authors and unconfigured channels are ignored" do
    assert_no_difference -> { Message.count } do
      assert_nil Connectors::Discord.ingest(payload("message_create_bot"))
      assert_nil Connectors::Discord.ingest(payload("message_create").merge("channel_id" => "1199999999999999999"))
    end
  end

  test "a paused source ignores its channel" do
    @source.update!(status: :paused)

    assert_no_difference -> { Message.count } do
      assert_nil Connectors::Discord.ingest(payload("message_create"))
    end
  end

  test "the same message id twice stores one message" do
    first = Connectors::Discord.ingest(payload("message_create"))

    second = nil
    assert_no_difference -> { Message.count } do
      second = Connectors::Discord.ingest(payload("message_create"))
    end

    assert second.duplicate?
    assert_equal first.message, second.message
  end

  test "a gateway disconnect records the error on each Discord source" do
    other = Source.create!(kind: :discord, name: "Cora Discord #help", selector: "1100000000000000002")

    Connectors::Discord.record_gateway_error!("disconnected, reconnecting")

    [ @source, other ].each do |source|
      assert_equal "Discord gateway: disconnected, reconnecting", source.reload.last_error
      assert_not source.healthy?
    end
    assert_nil sources(:slack_community).reload.last_error
  end

  test "reconnecting clears gateway errors but keeps other errors" do
    Connectors::Discord.record_gateway_error!("disconnected, reconnecting")
    other = Source.create!(kind: :discord, name: "Cora Discord #help", selector: "1100000000000000002",
      last_error: "Forbidden: missing access", last_error_at: 1.minute.ago)

    Connectors::Discord.clear_gateway_errors!

    assert_nil @source.reload.last_error
    assert_equal "Forbidden: missing access", other.reload.last_error
  end

  private

  def payload(name)
    JSON.parse(file_fixture("discord/#{name}.json").read)
  end
end
