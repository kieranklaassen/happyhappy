require "test_helper"

class Webhooks::PayloadTest < ActiveSupport::TestCase
  test "the item carries its actionability score and band" do
    event = item_events(:angry_slack_classified)
    event.item.update!(actionability: 0.93, actionability_band: "act_now")

    payload = Webhooks::Payload.for_event(event, "item.classified")

    assert_equal({ score: 0.93, band: "act_now" }, payload[:item][:actionability])
    assert_equal "act_now", Webhooks::Payload.sample.dig(:item, :actionability, :band)
  end
end
