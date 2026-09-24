require "test_helper"

class ItemEventTest < ActiveSupport::TestCase
  test "covers every timeline kind" do
    assert_equal %w[arrived classified classification_failed corrected claimed released reassigned reported
      status_changed overdue escalated], ItemEvent.kinds.keys
  end

  test "is append-only" do
    event = item_events(:angry_slack_arrived)

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(kind: "classified") }
  end

  test "actor is a user, an agent, or the system" do
    assert_equal "Cursor", item_events(:claimed_intercom_claimed).actor_label
    assert_equal "one@example.com", item_events(:needs_review_x_corrected).actor_label
    assert_equal "happyhappy", item_events(:angry_slack_classified).actor_label

    event = ItemEvent.new(item: items(:angry_slack), kind: "arrived", actor: products(:cora))
    refute event.valid?
  end

  test "record_event! stores data on the item timeline" do
    event = items(:praise_discord).record_event!(:reported, actor: agents(:cursor), summary: "Thanked them", link: nil)

    assert event.persisted?
    assert_equal({ "summary" => "Thanked them", "link" => nil }, event.data)
  end
end
