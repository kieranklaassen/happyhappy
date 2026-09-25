require "test_helper"

class GetItemToolTest < ActiveSupport::TestCase
  test "returns messages, labels, and the timeline" do
    item = items(:claimed_intercom)
    payload = GetItemTool.call(item_id: item.id, server_context: { agent: agents(:baby_agent) }).structured_content["item"]

    assert_equal "claimed", payload["status"]
    assert_equal "Cursor", payload["claimed_by"]
    assert_equal item.messages.size, payload["messages"].size
    assert payload["messages"].all? { |message| message.dig("body", "untrusted") }
    assert_equal({ "value" => "complaint", "probability" => 0.75, "human_set" => false }, payload.dig("labels", "sentiment"))
    assert_equal [ "claimed" ], payload["timeline"].map { |event| event["kind"] }
  end

  test "an unknown id is a tool error" do
    response = GetItemTool.call(item_id: 0, server_context: { agent: agents(:cursor) })

    assert response.error?
    assert_equal "Item 0 was not found.", response.content.first[:text]
  end
end
