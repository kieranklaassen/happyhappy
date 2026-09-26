require "test_helper"

class Backfill::IntercomStatesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WebhookEndpointHelper

  API = Backfill::Intercom::API_URL

  setup do
    Item.where(source_kind: "intercom").update_all(status: "handled")
    source = sources(:intercom_inbox)
    @closed = intercom_item(source, "c-closed")
    @snoozed = intercom_item(source, "c-snoozed")
    @open = intercom_item(source, "c-open")
    @already_handled = intercom_item(source, "c-handled", status: "handled")
    @lead = intercom_item(source, "c-lead")
    @lead.messages.create!(source: source, external_id: "lead-2", body: "dana@example.com", occurred_at: 1.day.ago + 1.minute)

    stub_search(nil, { "conversations" => [ { "id" => "c-closed", "state" => "closed" }, { "id" => "c-lead", "state" => "closed" } ],
      "pages" => { "next" => { "starting_after" => "page-2" } } })
    stub_search("page-2", { "conversations" => [ { "id" => "c-snoozed", "state" => "snoozed" }, { "id" => "c-handled", "state" => "closed" } ],
      "pages" => {} })
  end

  test "closes items whose conversation is closed, records snoozed and open, and fills typed emails" do
    create_webhook_endpoint

    counts = nil
    assert_no_difference -> { WebhookDelivery.count } do
      counts = Backfill::IntercomStates.new(token: "test-token").call
    end

    assert_equal({ searched: 4, closed: 2, snoozed: 1, open: 1, emails: 1 }, counts.slice(:searched, :closed, :snoozed, :open, :emails))
    assert @closed.reload.status_handled?
    assert_equal "closed", @closed.external_state
    assert_equal "closed_in_intercom", @closed.events.where(kind: "status_changed").last.data["reason"]
    assert @snoozed.reload.status_new?
    assert_equal "snoozed", @snoozed.external_state
    assert_equal "open", @open.reload.external_state
    assert_nil @already_handled.reload.external_state, "resolved items are not fetched"
    assert_equal "dana@example.com", @lead.reload.author_email
  end

  test "a rerun changes nothing" do
    Backfill::IntercomStates.new(token: "test-token").call

    counts = Backfill::IntercomStates.new(token: "test-token").call

    assert_equal 0, counts[:closed]
    assert_equal 2, counts[:unchanged], "the snoozed and open items stay as they are"
  end

  private

  def intercom_item(source, conversation_id, status: "new")
    item = Item.create!(source: source, thread_key: conversation_id, status: status, last_message_at: 1.day.ago)
    item.messages.create!(source: source, external_id: "#{conversation_id}-1", body: "Help with my account", occurred_at: 1.day.ago)
    item
  end

  def stub_search(starting_after, body)
    stub_request(:post, "#{API}/conversations/search")
      .with { |request| JSON.parse(request.body).dig("pagination", "starting_after") == starting_after }
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end
end
