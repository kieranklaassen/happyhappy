require "test_helper"

class Connectors::PostmarkTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @source = sources(:support_email)
  end

  test "a first mail creates an item on the matching email source with the sender as author" do
    result = nil
    assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      result = Connectors::Postmark.call(payload("inbound_first"))
    end

    item = result.item
    assert_equal @source, item.source
    assert_equal "email", item.source_kind
    assert_equal products(:cora), item.product
    assert_equal "CAJx7=Qp1first0dana@mail.gmail.com", item.thread_key
    assert_equal "dana@example.com", item.author_email
    assert_equal "dana@example.com", item.author_handle
    assert_equal "Dana Customer", item.author_name

    message = result.message
    assert_equal "a8c1f0d2-3b4e-4f5a-9c6d-7e8f9a0b1c2d", message.external_id
    assert_match "stopped sorting anything into my Brief", message.body
    assert_equal Time.utc(2026, 9, 24, 13, 12, 45), message.occurred_at
    assert_enqueued_with job: ClassifyMessageJob, args: [ message ]
  end

  test "raw payload keeps attachment metadata but drops attachment content" do
    message = Connectors::Postmark.call(payload("inbound_first")).message

    attachment = message.raw_payload["Attachments"].sole
    assert_equal "screenshot.png", attachment["Name"]
    refute attachment.key?("Content")
    assert_equal "Cora stopped sorting my inbox", message.raw_payload["Subject"]
  end

  test "a reply joins the original item through the first References id and uses the stripped reply" do
    first = Connectors::Postmark.call(payload("inbound_first"))

    reply = nil
    assert_no_difference -> { Item.count } do
      reply = Connectors::Postmark.call(payload("inbound_reply"))
    end

    assert_equal first.item, reply.item
    assert_equal "Still broken this morning, and now my Brief is empty too.", reply.message.body
    assert_equal 2, first.item.messages.count
  end

  test "a reply with only In-Reply-To joins the original item" do
    first = Connectors::Postmark.call(payload("inbound_first"))
    reply = payload("inbound_reply")
    reply["Headers"].reject! { |header| header["Name"] == "References" }
    set_header(reply, "In-Reply-To", "<CAJx7=Qp1first0dana@mail.gmail.com>")

    assert_equal first.item, Connectors::Postmark.call(reply).item
  end

  test "header names match case-insensitively" do
    first = Connectors::Postmark.call(payload("inbound_first"))
    reply = payload("inbound_reply")
    reply["Headers"].find { |header| header["Name"] == "References" }["Name"] = "REFERENCES"

    assert_equal first.item, Connectors::Postmark.call(reply).item
  end

  test "a mail with no threading headers falls back to the sender and normalized subject" do
    first = payload("inbound_first")
    first["Headers"].reject! { |header| header["Name"] == "Message-ID" }
    reply = payload("inbound_reply")
    reply["Headers"].reject! { |header| %w[Message-ID In-Reply-To References].include?(header["Name"]) }
    reply["Subject"] = "RE: Fwd:  Cora stopped   sorting my inbox"

    first_item = Connectors::Postmark.call(first).item

    assert_equal "dana@example.com|cora stopped sorting my inbox", first_item.thread_key
    assert_equal first_item, Connectors::Postmark.call(reply).item
  end

  test "the recipient address matches case-insensitively" do
    mail = payload("inbound_first")
    mail["ToFull"].first["Email"] = "Help@Cora.Computer"

    assert_equal @source, Connectors::Postmark.call(mail).item.source
  end

  test "a source selected by its Postmark inbound address matches OriginalRecipient" do
    source = Source.create!(kind: :email, name: "Postmark inbound", selector: "3f9c2e1b7a4d4c0e9b1f@inbound.postmarkapp.com")

    assert_equal source, Connectors::Postmark.call(payload("inbound_first")).item.source
  end

  test "a Cc recipient routes the mail when no To address matches" do
    mail = payload("inbound_first")
    mail["ToFull"] = [ { "Email" => "someone@example.com", "Name" => "", "MailboxHash" => "" } ]
    mail["CcFull"] = [ { "Email" => "help@cora.computer", "Name" => "", "MailboxHash" => "" } ]

    assert_equal @source, Connectors::Postmark.call(mail).item.source
  end

  test "an unknown recipient stores nothing and returns nil" do
    mail = payload("inbound_first")
    mail["ToFull"] = [ { "Email" => "nobody@example.com", "Name" => "", "MailboxHash" => "" } ]

    assert_no_difference -> { Item.count } do
      assert_nil Connectors::Postmark.call(mail)
    end
  end

  test "the same MessageID twice stores one message (R10)" do
    Connectors::Postmark.call(payload("inbound_first"))

    result = nil
    assert_no_difference -> { Message.count } do
      result = Connectors::Postmark.call(payload("inbound_first"))
    end
    assert result.duplicate?
  end

  test "an HTML-only mail uses the HTML body as plain text" do
    mail = payload("inbound_first")
    mail["TextBody"] = ""

    body = Connectors::Postmark.call(mail).message.body

    assert_equal [ "Hi,", "Since yesterday Cora has stopped sorting anything into my Brief. " \
      "Everything lands in the inbox again.", "Dana" ], body.split(/\n+/)
  end

  test "a payload without a MessageID records the error on the source and raises" do
    mail = payload("inbound_first")
    mail.delete("MessageID")

    assert_raises(ActiveModel::ValidationError) { Connectors::Postmark.call(mail) }
    assert_match "External can't be blank", @source.reload.last_error
  end

  private

  def payload(name)
    JSON.parse(file_fixture("postmark/#{name}.json").read)
  end

  def set_header(payload, name, value)
    header = payload["Headers"].find { |candidate| candidate["Name"] == name }
    header["Value"] = value
  end
end
