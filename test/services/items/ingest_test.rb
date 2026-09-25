require "test_helper"

class Items::IngestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @source = sources(:discord_spiral)
  end

  test "a new message creates one item, one message, and one arrived event, and enqueues classification" do
    result = nil

    assert_difference -> { Item.count } => 1, -> { Message.count } => 1, -> { ItemEvent.count } => 1 do
      result = ingest(external_id: "m-1", thread_key: "t-1")
    end

    refute result.duplicate?
    item = result.item
    assert item.status_new?
    assert_equal "discord", item.source_kind
    assert_equal @source, item.source
    assert_equal products(:spiral), item.product
    assert_equal "writer", item.author_handle
    assert_equal "https://discord.com/channels/1/2/m-1", item.permalink
    assert_equal "Spiral is great", result.message.body
    assert_equal({ "id" => "m-1" }, result.message.raw_payload)
    assert_equal [ "arrived" ], item.events.map(&:kind)
    assert_equal result.message.id, item.events.last.data["message_id"]
    assert_enqueued_with job: ClassifyMessageJob, args: [ result.message ]
  end

  test "the same external id twice keeps one message and one event (R10)" do
    first = ingest(external_id: "m-1", thread_key: "t-1")
    clear_enqueued_jobs

    second = nil
    assert_no_difference -> { Message.count } do
      assert_no_difference -> { ItemEvent.count } do
        second = ingest(external_id: "m-1", thread_key: "t-1", body: "retried delivery")
      end
    end

    assert second.duplicate?
    assert_equal first.message, second.message
    assert_equal first.item, second.item
    assert_no_enqueued_jobs
  end

  test "a second message on the same thread key attaches to the existing item" do
    first = ingest(external_id: "m-1", thread_key: "t-1", occurred_at: 10.minutes.ago)
    reply_time = 1.minute.ago.change(usec: 0)

    second = nil
    assert_no_difference -> { Item.count } do
      second = ingest(external_id: "m-2", thread_key: "t-1", occurred_at: reply_time)
    end

    assert_equal first.item, second.item
    assert_equal 2, first.item.messages.count
    assert_equal reply_time, second.item.reload.last_message_at
  end

  test "an older message does not move last message at backwards" do
    first = ingest(external_id: "m-1", thread_key: "t-1", occurred_at: 1.minute.ago)
    latest = first.item.last_message_at

    ingest(external_id: "m-0", thread_key: "t-1", occurred_at: 1.hour.ago)

    assert_equal latest, first.item.reload.last_message_at
  end

  test "a new message on a handled item sets it back to new and writes a status event" do
    item = items(:handled_email)

    result = ingest(source: sources(:support_email), external_id: "<reply-2@mail.example.com>",
      thread_key: item.thread_key, body: "That did not work")

    assert_equal item, result.item
    assert item.reload.status_new?
    assert_equal %w[arrived status_changed], item.events.last(2).map(&:kind)
    assert_equal({ "from" => "handled", "to" => "new", "reason" => "customer_wrote_again",
      "message_id" => result.message.id }, item.events.last.data)
    assert_equal [ result.message ], item.open_messages.to_a
  end

  test "a team reply on a handled item keeps it handled, keeps its author, and is not the customer's latest activity" do
    item = items(:handled_email)
    last_message_at = item.last_message_at

    result = ingest(source: sources(:support_email), external_id: "<team-1@every.to>", thread_key: item.thread_key,
      body: "Glad that worked!", author_handle: "kieran@every.to", author_email: "kieran@every.to")

    assert result.message.author_team?
    item.reload
    assert item.status_handled?
    assert_equal "cy@example.com", item.author_email
    assert_equal last_message_at, item.last_message_at
    assert_equal "team", item.events.last.data["author_role"]
  end

  test "a thread a team member opens takes its author from the first customer who replies" do
    ingest(source: sources(:support_email), external_id: "<t-1@every.to>", thread_key: "<t-1@every.to>",
      body: "New release is out", author_handle: "kieran@every.to", author_email: "kieran@every.to")
    result = ingest(source: sources(:support_email), external_id: "<t-2@example.com>", thread_key: "<t-1@every.to>",
      body: "It broke my drafts", author_handle: "ana@example.com", author_email: "ana@example.com")

    assert result.message.author_customer?
    assert_equal "ana@example.com", result.item.reload.author_email
  end

  test "a new message on a dismissed item sets it back to new" do
    item = items(:retired_product_slack)

    ingest(source: sources(:lex_legacy), external_id: "C0LEXLEGACY:1", thread_key: item.thread_key)

    assert item.reload.status_new?
  end

  test "a new message on a claimed item keeps its status and adds an arrived event" do
    item = items(:claimed_intercom)

    assert_difference -> { item.events.count }, 1 do
      ingest(source: sources(:intercom_inbox), external_id: "part-2", thread_key: item.thread_key)
    end

    assert item.reload.status_claimed?
    assert_equal agents(:cursor), item.claimed_by_agent
    assert item.events.last.arrived?
  end

  test "a new message on an in-progress item keeps its status" do
    item = items(:claimed_intercom)
    item.update!(status: "in_progress")

    ingest(source: sources(:intercom_inbox), external_id: "part-3", thread_key: item.thread_key)

    assert item.reload.status_in_progress?
  end

  test "the same thread key through a second source of the same kind attaches to the existing item" do
    item = items(:angry_slack)
    other_slack = sources(:lex_legacy)

    result = ingest(source: other_slack, external_id: "C0LEXLEGACY:#{item.thread_key}", thread_key: item.thread_key)

    assert_equal item, result.item
    assert_equal sources(:slack_community), item.reload.source
    assert_equal other_slack, result.message.source
  end

  test "the same thread key on a different source kind is a different item" do
    result = ingest(external_id: "m-1", thread_key: items(:angry_slack).thread_key)

    refute_equal items(:angry_slack), result.item
  end

  test "a message for a retired product's source still ingests and keeps the product readable (R7)" do
    source = sources(:lex_legacy)

    result = ingest(source: source, external_id: "C0LEXLEGACY:new", thread_key: "new-thread")

    assert result.item.persisted?
    assert_equal products(:lex), result.item.product
    assert result.item.product.retired?
  end

  test "ingest updates the source's last message time and clears its last error" do
    source = sources(:lex_legacy)

    freeze_time do
      ingest(source: source, external_id: "C0LEXLEGACY:2", thread_key: "t-2")

      assert_equal Time.current, source.reload.last_message_at
    end
    assert_nil source.last_error
    assert_nil source.last_error_at
  end

  test "an inbound message missing an external id raises a validation error and stores nothing" do
    assert_no_difference [ -> { Item.count }, -> { Message.count }, -> { ItemEvent.count } ] do
      assert_raises(ActiveModel::ValidationError) do
        ingest(external_id: nil, thread_key: "t-1")
      end
    end
    assert_no_enqueued_jobs
  end

  test "an inbound message missing a thread key raises a validation error" do
    assert_raises(ActiveModel::ValidationError) { ingest(external_id: "m-1", thread_key: " ") }
  end

  test "a failure after the item is created rolls everything back" do
    @source.define_singleton_method(:record_message_received!) { |*| raise ActiveRecord::RecordInvalid }

    assert_no_difference [ -> { Item.count }, -> { Message.count }, -> { ItemEvent.count } ] do
      assert_raises(ActiveRecord::RecordInvalid) { ingest(external_id: "m-1", thread_key: "t-1") }
    end
    assert_no_enqueued_jobs
  end

  test "defaults occurred at to now and keeps an empty body" do
    freeze_time do
      inbound = Items::InboundMessage.new(external_id: "m-1", thread_key: "t-1", body: nil)

      assert_equal Time.current, inbound.occurred_at
      assert_equal "", inbound.body
    end
  end

  test "a backfilled message is flagged, marks its events, and classifies on the backfill queue" do
    result = ingest(external_id: "m-1", thread_key: "t-1", occurred_at: 30.days.ago, backfill: true)

    assert result.message.backfilled?
    assert_equal true, result.item.events.sole.data["backfill"]
    assert_enqueued_with job: ClassifyMessageJob, args: [ result.message ], queue: "backfill"

    use_fake_classifier(product: "spiral")
    perform_enqueued_jobs(only: ClassifyMessageJob)
    assert_equal true, result.item.events.reload.find_by(kind: "classified").data["backfill"]
  end

  test "a live message is not flagged and its events carry no backfill marker" do
    result = ingest(external_id: "m-1", thread_key: "t-1")

    refute result.message.backfilled?
    refute result.item.events.sole.data.key?("backfill")
    assert_enqueued_with job: ClassifyMessageJob, args: [ result.message ], queue: "realtime"
  end

  test "a backfilled message never reopens a handled item" do
    item = ingest(external_id: "m-1", thread_key: "t-1").item
    item.change_status!(:handled)

    ingest(external_id: "m-0", thread_key: "t-1", occurred_at: 20.days.ago, backfill: true)

    assert item.reload.status_handled?
    assert_equal 2, item.messages.count
  end

  test "a message already on its thread through another source of the same kind is a duplicate" do
    catch_all = Source.create!(kind: "discord", name: "Other channel", selector: "2200000000000000002",
      default_product: products(:spiral), status: "active")
    first = ingest(source: catch_all, external_id: "m-1", thread_key: "t-1")

    second = nil
    assert_no_difference [ -> { Message.count }, -> { ItemEvent.count } ] do
      second = ingest(external_id: "m-1", thread_key: "t-1", backfill: true)
    end
    assert second.duplicate?
    assert_equal first.message, second.message
  end

  test "rerunning a backfill dedupes on the external id" do
    ingest(external_id: "m-1", thread_key: "t-1", backfill: true)

    rerun = nil
    assert_no_difference [ -> { Message.count }, -> { ItemEvent.count } ] do
      rerun = ingest(external_id: "m-1", thread_key: "t-1", backfill: true)
    end
    assert rerun.duplicate?
  end

  private

  def ingest(source: @source, backfill: false, **attributes)
    Items::Ingest.call(source: source, inbound: inbound_message(**attributes), backfill: backfill)
  end

  def inbound_message(external_id:, thread_key:, body: "Spiral is great", occurred_at: Time.current,
    author_handle: "writer", author_email: nil)
    Items::InboundMessage.new(
      external_id: external_id,
      thread_key: thread_key,
      body: body,
      occurred_at: occurred_at,
      author_handle: author_handle,
      author_email: author_email,
      permalink: "https://discord.com/channels/1/2/#{external_id}",
      raw_payload: { "id" => external_id }
    )
  end
end
