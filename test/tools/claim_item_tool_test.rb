require "test_helper"

class ClaimItemToolTest < ActiveSupport::TestCase
  def call(item, agent)
    ClaimItemTool.call(item_id: item.id, server_context: { agent: agent })
  end

  test "claims a new item for the calling agent" do
    payload = call(items(:praise_discord), agents(:baby_agent)).structured_content["item"]

    assert_equal "claimed", payload["status"]
    assert_equal "Baby Agent", payload["claimed_by"]
    assert_equal agents(:baby_agent), items(:praise_discord).reload.claimed_by_agent
  end

  test "a handled item cannot be claimed" do
    response = call(items(:handled_email), agents(:cursor))

    assert response.error?
    assert_match "only new items can be claimed", response.content.first[:text]
  end

  test "a revoked agent cannot claim" do
    response = call(items(:praise_discord), agents(:revoked))

    assert response.error?
    assert_equal "The agent token was revoked.", response.content.first[:text]
  end
end
