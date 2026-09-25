require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  include McpHelper

  setup { host! "localhost" }

  test "tools/list returns the six tools for a valid token" do
    body = mcp_request("tools/list")

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Mcp-Session-Id"]
    names = body.dig("result", "tools").map { |tool| tool["name"] }
    assert_equal %w[list_items get_item claim_item release_item report_item list_anomalies], names
  end

  test "initialize answers with the server name and untrusted content instructions" do
    body = mcp_request("initialize", {
      protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" }
    })

    assert_response :success
    assert_equal "happyhappy", body.dig("result", "serverInfo", "name")
    assert_match "untrusted", body.dig("result", "instructions")
  end

  test "no token returns 401" do
    mcp_request("tools/list", token: nil)

    assert_response :unauthorized
    assert_match "Bearer", response.headers["WWW-Authenticate"]
    assert_equal "An agent token is required.", response.parsed_body["error"]
  end

  test "a revoked token returns 401" do
    mcp_request("tools/list", token: "revoked-test-token")

    assert_response :unauthorized
    assert_equal "The agent token was revoked.", response.parsed_body["error"]
  end

  test "an unknown token returns 401" do
    mcp_request("tools/list", token: "not-a-token")

    assert_response :unauthorized
  end

  test "a request records the agent's last use" do
    freeze_time do
      mcp_request("tools/list", token: "baby-agent-test-token")

      assert_equal Time.current, agents(:baby_agent).reload.last_used_at
    end
  end

  test "a failed authentication does not record use" do
    assert_no_changes -> { agents(:revoked).reload.last_used_at } do
      mcp_request("tools/list", token: "revoked-test-token")
    end
  end

  test "list_items with product and sentiment filters returns matching items" do
    payload = tool_payload(mcp_tool("list_items", { product: "cora", sentiment: [ "complaint" ] }))

    ids = payload["items"].map { |item| item["id"] }
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ], ids
    assert_equal({ "product" => [ "cora" ], "sentiment" => [ "complaint" ], "relevance" => "relevant" }, payload["filters"])
  end

  test "an invalid filter comes back as a tool error naming the filter" do
    assert_match "sentiment", tool_error_text(mcp_tool("list_items", { sentiment: [ "furious" ] }))
    assert_match "is not a filter", tool_error_text(mcp_tool("list_items", { mood: "grumpy" }))
  end

  test "claim_item then report_item with handled changes status and appears on the timeline" do
    item = items(:angry_slack)

    claimed = tool_payload(mcp_tool("claim_item", { item_id: item.id }))["item"]
    assert_equal "claimed", claimed["status"]
    assert_equal "Cursor", claimed["claimed_by"]

    reported = tool_payload(mcp_tool("report_item", {
      item_id: item.id, summary: "Restored the inbox and replied.", status: "handled", link: "https://example.com/reply/1"
    }))["item"]

    assert_equal "handled", reported["status"]
    assert_nil reported["claimed_by"]
    report = reported["timeline"].find { |event| event["kind"] == "reported" }
    assert_equal({ "type" => "Agent", "name" => "Cursor" }, report["actor"])
    assert_equal "Restored the inbox and replied.", report["data"]["summary"]
    assert_equal "https://example.com/reply/1", report["data"]["link"]
    assert item.reload.status_handled?
  end

  test "claim_item on a taken item returns a tool error naming the conflict" do
    text = tool_error_text(mcp_tool("claim_item", { item_id: items(:claimed_intercom).id }, token: "baby-agent-test-token"))

    assert_equal "Item #{items(:claimed_intercom).id} is already claimed by Cursor.", text
    assert_equal agents(:cursor), items(:claimed_intercom).reload.claimed_by_agent
  end

  test "release_item returns the agent's claim to new" do
    item = tool_payload(mcp_tool("release_item", { item_id: items(:claimed_intercom).id }))["item"]

    assert_equal "new", item["status"]
    assert_nil item["claimed_by"]
  end

  test "another agent cannot release or report on a claim" do
    id = items(:claimed_intercom).id

    assert_match "not claimed by Baby Agent",
      tool_error_text(mcp_tool("release_item", { item_id: id }, token: "baby-agent-test-token"))
    assert_match "not claimed by Baby Agent",
      tool_error_text(mcp_tool("report_item", { item_id: id, summary: "Done", status: "handled" }, token: "baby-agent-test-token"))
    assert items(:claimed_intercom).reload.status_claimed?
  end

  test "get_item for an unknown id returns a tool error" do
    assert_equal "Item 0 was not found.", tool_error_text(mcp_tool("get_item", { item_id: 0 }))
  end

  test "item payloads mark customer message bodies as untrusted content" do
    item = tool_payload(mcp_tool("get_item", { item_id: items(:angry_slack).id }))["item"]

    body = item["messages"].first["body"]
    assert_equal true, body["untrusted"]
    assert_equal messages(:angry_slack_first).body, body["text"]
    assert_equal({ "untrusted" => true, "handle" => "ana_customer", "name" => "Ana Customer", "email" => nil }, item["author"])
    assert_equal items(:angry_slack).permalink, item["permalink"]
    assert_equal 0.92, item.dig("labels", "product", "probability")

    listed = tool_payload(mcp_tool("list_items", { product: [ "cora" ] }))["items"].first
    assert_equal true, listed.dig("excerpt", "untrusted")
    assert_equal items(:angry_slack).messages.last.body, listed.dig("excerpt", "text")
  end

  test "the public host from PUBLIC_BASE_URL is accepted and other hosts are refused" do
    original = Rails.configuration.x.public_base_url
    Rails.configuration.x.public_base_url = "https://happyhappy.every.to"

    host! "happyhappy.every.to"
    mcp_request("tools/list", headers: { "Origin" => "https://happyhappy.every.to" })
    assert_response :success

    host! "evil.example.com"
    mcp_request("tools/list")
    assert_response :forbidden
  ensure
    Rails.configuration.x.public_base_url = original
  end
end
