require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "statuses follow the lifecycle names" do
    assert_equal %w[new claimed in_progress handled dismissed], Item.statuses.keys
    assert items(:angry_slack).status_new?
    assert items(:claimed_intercom).status_claimed?
  end

  test "sentiments are complaint, praise, question, and neutral" do
    assert_equal %w[complaint praise question neutral], Item.sentiments.keys
  end

  test "thread key is unique per source kind" do
    duplicate = Item.new(source: sources(:lex_legacy), thread_key: items(:angry_slack).thread_key,
      last_message_at: Time.current)

    refute duplicate.valid?
    assert duplicate.errors.key?(:thread_key)
  end

  test "copies the source kind and stamps status changed at" do
    item = Item.create!(source: sources(:discord_spiral), thread_key: "999", last_message_at: Time.current)

    assert_equal "discord", item.source_kind
    assert item.status_changed_at.present?
    assert item.relevant?
    refute item.needs_review?
  end

  test "rejects probabilities outside 0 to 1" do
    item = items(:angry_slack)
    item.anger_probability = 1.2

    refute item.valid?
  end

  test "change_status! writes a status_changed event with the actor" do
    item = items(:angry_slack)
    user = users(:every_ana)

    assert_difference -> { item.events.count }, 1 do
      assert item.change_status!(:dismissed, actor: user)
    end

    event = item.events.last
    assert item.reload.status_dismissed?
    assert event.status_changed?
    assert_equal({ "from" => "new", "to" => "dismissed" }, event.data)
    assert_equal user, event.actor
  end

  test "change_status! to the same status does nothing" do
    item = items(:angry_slack)

    assert_no_difference -> { ItemEvent.count } do
      refute item.change_status!(:new)
    end
  end

  test "open messages are those received since the last status change" do
    item = items(:angry_slack)
    assert_equal 2, item.open_messages.count

    item.update!(status_changed_at: 100.minutes.ago)
    assert_equal [ messages(:unclassified_slack_reply) ], item.open_messages.to_a
  end

  test "messages and events read in time order" do
    item = items(:angry_slack)

    assert_equal [ messages(:angry_slack_first), messages(:unclassified_slack_reply) ], item.messages.to_a
    assert_equal %w[arrived classified], item.events.map(&:kind)
  end

  test "publish_classified instruments item.classified with the item id" do
    item = items(:angry_slack)
    payloads = []
    callback = ->(*, payload) { payloads << payload }

    ActiveSupport::Notifications.subscribed(callback, Item::CLASSIFIED_EVENT) do
      item.publish_classified(messages(:angry_slack_first))
    end

    assert_equal "item.classified", Item::CLASSIFIED_EVENT
    assert_equal [ { item_id: item.id, message_id: messages(:angry_slack_first).id } ], payloads
  end

  test "claimed by an agent" do
    assert_equal agents(:cursor), items(:claimed_intercom).claimed_by_agent
    assert_includes agents(:cursor).claimed_items, items(:claimed_intercom)
  end

  test "scopes" do
    assert_not_includes Item.relevant, items(:not_relevant_slack)
    assert_includes Item.unresolved, items(:claimed_intercom)
    assert_not_includes Item.unresolved, items(:handled_email)
    assert_not_includes Item.unclaimed, items(:claimed_intercom)
    assert_equal items(:needs_review_x), Item.recent_first.first
  end
end
