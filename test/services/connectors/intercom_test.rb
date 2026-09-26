require "test_helper"

class Connectors::IntercomTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include IntercomPayloads

  setup do
    @source = sources(:intercom_inbox)
  end

  test "conversation.user.created stores the opening message keyed by conversation id" do
    result = nil
    assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      result = Connectors::Intercom.call(intercom_created)
    end

    item = result.item
    assert_equal "intercom", item.source_kind
    assert_equal "215470000000777", item.thread_key
    assert_equal @source, item.source
    assert_equal "Casey Customer", item.author_name
    assert_equal "casey@example.com", item.author_email
    assert_equal "https://app.intercom.com/a/inbox/abc123/inbox/conversation/215470000000777", item.permalink

    message = result.message
    assert_equal "2254000000777", message.external_id
    assert_equal Time.zone.at(1790276400), message.occurred_at
    assert_equal "conversation.user.created", message.raw_payload["topic"]
    assert_equal "2254000000777", message.raw_payload.dig("part", "id")
    assert_enqueued_with job: ClassifyMessageJob, args: [ message ]
  end

  test "HTML bodies are stored as plain text" do
    message = Connectors::Intercom.call(intercom_created).message

    assert_equal "Cora stopped sorting my inbox this morning.\nNothing has moved to Brief since 9am & I have 200 unread emails.",
      message.body
  end

  test "conversation.user.replied stores only the newest part, as plain text" do
    Connectors::Intercom.call(intercom_created)

    result = Connectors::Intercom.call(intercom_replied)

    assert_equal "31990000000002", result.message.external_id
    assert_equal "I reconnected it twice.\nStill nothing. This is the third time this month!", result.message.body
    assert_equal Time.zone.at(1790277300), result.message.occurred_at
    assert_equal 2, result.item.messages.count
  end

  test "covers AE5 ingest half: three replies in one conversation add three messages to one item" do
    Connectors::Intercom.call(intercom_created)

    assert_difference -> { Item.count } => 0, -> { Message.count } => 3 do
      %w[r-1 r-2 r-3].each do |part_id|
        Connectors::Intercom.call(intercom_replied(id: part_id, body: "<p>Still broken (#{part_id})</p>"))
      end
    end

    item = Item.find_by!(source_kind: "intercom", thread_key: "215470000000777")
    assert_equal 4, item.messages.count
    assert_equal 4, item.events.where(kind: "arrived").count
  end

  test "a resent notification stores the message once" do
    Connectors::Intercom.call(intercom_replied)

    result = nil
    assert_no_difference -> { Message.count } do
      result = Connectors::Intercom.call(intercom_replied)
    end
    assert result.duplicate?
  end

  test "admin replies, notes, and bot parts are ignored" do
    [
      intercom_replied(author_type: "admin"),
      intercom_replied(author_type: "bot"),
      intercom_replied(part_type: "note"),
      intercom_replied(part_type: "assignment")
    ].each do |payload|
      assert_no_difference -> { Message.count } do
        assert_nil Connectors::Intercom.call(payload)
      end
    end
  end

  test "a customer reply that reopens a closed conversation is stored" do
    result = Connectors::Intercom.call(intercom_replied(part_type: "open", body: "<p>Back again, still broken</p>"))

    assert_equal "Back again, still broken", result.message.body
  end

  test "a reopen without a customer message is ignored" do
    assert_nil Connectors::Intercom.call(intercom_replied(part_type: "open", body: nil))
    assert_nil Connectors::Intercom.call(intercom_replied(part_type: "open", author_type: "admin"))
  end

  test "lead authors are customers too" do
    assert Connectors::Intercom.call(intercom_replied(author_type: "lead"))
  end

  test "other topics and malformed payloads are ignored" do
    other = intercom_created.merge("topic" => "conversation.admin.replied")

    assert_no_difference -> { Message.count } do
      [ other, { "topic" => "ping" }, {}, [], nil ].each do |payload|
        assert_nil Connectors::Intercom.call(payload)
      end
    end
  end

  test "an empty body after stripping HTML is ignored" do
    assert_nil Connectors::Intercom.call(intercom_replied(body: "<p> </p>"))
  end

  test "a conversation assigned to no configured team goes to the catch-all source" do
    catch_all = Source.create!(kind: "intercom", name: "Everything else", selector: "*")
    payload = intercom_created
    payload["data"]["item"]["team_assignee_id"] = "9999999"

    assert_equal catch_all, Connectors::Intercom.call(payload).message.source
  end

  test "an unassigned conversation goes to the catch-all source" do
    catch_all = Source.create!(kind: "intercom", name: "Everything else", selector: "*")
    payload = intercom_created
    payload["data"]["item"]["team_assignee_id"] = nil

    assert_equal catch_all, Connectors::Intercom.call(payload).message.source
  end

  test "with no matching source and no catch-all nothing is stored" do
    payload = intercom_created
    payload["data"]["item"]["team_assignee_id"] = "9999999"

    assert_no_difference -> { Message.count } do
      assert_nil Connectors::Intercom.call(payload)
    end
  end

  test "a paused source does not ingest" do
    @source.update!(status: "paused")

    assert_nil Connectors::Intercom.call(intercom_created)
  end

  test "a paused source does not fall through to the catch-all source" do
    @source.update!(status: "paused")
    Source.create!(kind: "intercom", name: "Everything else", selector: "*")

    assert_no_difference -> { Message.count } do
      assert_nil Connectors::Intercom.call(intercom_created)
    end
  end

  test "a reassigned conversation stays on its item and source" do
    first = Connectors::Intercom.call(intercom_created)
    reassigned = intercom_replied
    reassigned["data"]["item"]["team_assignee_id"] = "9999999"

    result = Connectors::Intercom.call(reassigned)

    assert_equal first.item, result.item
    assert_equal @source, result.message.source
  end

  test "an admin close in Intercom marks the item handled and records the conversation closed" do
    item = Connectors::Intercom.call(intercom_created).item
    assert_equal "open", item.reload.external_state

    assert_nil Connectors::Intercom.call(admin_state_change("closed", topic: "conversation.admin.closed"))

    item.reload
    assert item.status_handled?
    assert_equal "closed", item.external_state
    event = item.events.where(kind: "status_changed").last
    assert_equal({ "from" => "new", "to" => "handled", "reason" => "closed_in_intercom" }, event.data.slice("from", "to", "reason"))
  end

  test "an admin close releases the agent holding the item" do
    item = Connectors::Intercom.call(intercom_created).item
    agent = agents(:cursor)
    Agents::Claim.call(agent: agent, item: item)

    Connectors::Intercom.call(admin_state_change("closed", topic: "conversation.admin.closed"))

    item.reload
    assert item.status_handled?
    assert_nil item.claimed_by_agent_id
    assert_nil item.claimed_at
    assert_equal agent.name, item.events.where(kind: "status_changed").last.data["released_agent"]
  end

  test "a snooze records the state and leaves the status alone" do
    item = Connectors::Intercom.call(intercom_created).item

    Connectors::Intercom.call(admin_state_change("snoozed", topic: "conversation.admin.snoozed"))

    item.reload
    assert item.status_new?
    assert_equal "snoozed", item.external_state
    assert_not Item.needing_attention.exists?(item.id)
  end

  test "a customer writing into a closed conversation reopens the item" do
    item = Connectors::Intercom.call(intercom_created).item
    Connectors::Intercom.call(admin_state_change("closed", topic: "conversation.admin.closed"))

    Connectors::Intercom.call(intercom_replied(id: "reopen-1", part_type: "open", body: "<p>It broke again</p>"))

    item.reload
    assert item.status_new?
    assert_equal "open", item.external_state
    assert Item.needing_attention.exists?(item.id)
  end

  test "a state change for a conversation happyhappy never saw is ignored" do
    assert_no_difference [ -> { Item.count }, -> { ItemEvent.count } ] do
      Connectors::Intercom.call(admin_state_change("closed", topic: "conversation.admin.closed"))
    end
  end

  test "an email address typed into Fin becomes the author email of an unidentified lead" do
    Connectors::Intercom.call(intercom_replied(id: "fin-1", body: "<p>I was charged but still see the paywall</p>").tap { |payload| strip_author(payload) })
    result = Connectors::Intercom.call(intercom_replied(id: "fin-2", body: "<p>dana@example.com</p>").tap { |payload| strip_author(payload) })

    assert_equal "dana@example.com", result.item.reload.author_email
    assert_equal "dana@example.com", result.message.body
  end

  test "valid_signature? checks the sha1 HMAC of the raw body" do
    body = '{"topic":"ping"}'
    header = "sha1=#{OpenSSL::HMAC.hexdigest("SHA1", "shh", body)}"

    assert Connectors::Intercom.valid_signature?(body, header, secret: "shh")
    refute Connectors::Intercom.valid_signature?(body, header, secret: "other")
    refute Connectors::Intercom.valid_signature?("#{body} ", header, secret: "shh")
    refute Connectors::Intercom.valid_signature?(body, nil, secret: "shh")
    refute Connectors::Intercom.valid_signature?(body, header, secret: nil)
  end

  private

  # The recorded conversation after an admin changes its state, as Intercom sends it.
  def admin_state_change(state, topic:)
    intercom_replied.tap do |payload|
      payload["topic"] = topic
      payload["data"]["item"]["state"] = state
      payload["data"]["item"]["open"] = state == "open"
      part = payload.dig("data", "item", "conversation_parts", "conversation_parts").last
      part.merge!("id" => "state-#{state}", "part_type" => state == "closed" ? "close" : "snoozed", "body" => nil)
      part["author"] = { "type" => "admin", "id" => "5500001", "name" => "Sam Support", "email" => "sam@every.to" }
    end
  end

  def strip_author(payload)
    payload.dig("data", "item", "conversation_parts", "conversation_parts").last["author"] =
      { "type" => "user", "id" => "66f0c0ffee0000000000beef", "name" => nil, "email" => "" }
  end
end
