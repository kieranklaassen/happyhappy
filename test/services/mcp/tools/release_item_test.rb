require "test_helper"

class Mcp::Tools::ReleaseItemTest < ActiveSupport::TestCase
  def call(item, agent)
    Mcp::Tools::ReleaseItem.call(item_id: item.id, server_context: { agent: agent })
  end

  test "releases the agent's own claim" do
    payload = call(items(:claimed_intercom), agents(:cursor)).structured_content["item"]

    assert_equal "new", payload["status"]
    assert_equal "released", payload["timeline"].last["kind"]
  end

  test "an unclaimed item cannot be released" do
    response = call(items(:angry_slack), agents(:cursor))

    assert response.error?
    assert_equal "Item #{items(:angry_slack).id} is not claimed by Cursor.", response.content.first[:text]
  end
end
