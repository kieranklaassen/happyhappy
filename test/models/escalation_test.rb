require "test_helper"

class EscalationTest < ActiveSupport::TestCase
  test "belongs to an item, product, and message with a Slack channel" do
    escalation = escalations(:angry_slack_posted)

    assert escalation.posted?
    assert_equal items(:angry_slack), escalation.item
    assert_equal products(:cora), escalation.product
    assert_equal messages(:angry_slack_first), escalation.message
    assert_includes items(:angry_slack).escalations, escalation
  end

  test "an unposted escalation is kept as pending" do
    escalation = Escalation.create!(item: items(:praise_discord), product: products(:spiral),
      slack_channel_id: "C0SPIRALSUPPORT", last_error: "Slack 503")

    assert_includes Escalation.pending, escalation
    refute escalation.posted?
  end

  test "requires a Slack channel" do
    refute Escalation.new(item: items(:angry_slack), product: products(:cora)).valid?
  end
end
