require "test_helper"

class WebmcpToolsControllerTest < ActionDispatch::IntegrationTest
  include McpHelper

  setup do
    host! "localhost"
    @user = users(:every_ana)
    sign_in_as @user
  end

  test "signed out gets 401 for tool calls" do
    sign_out

    assert_no_changes -> { items(:angry_slack).reload.status } do
      webmcp_tool("claim_item", { item_id: items(:angry_slack).id })
    end
    assert_response :unauthorized
    assert_equal "Sign in to happyhappy to use its tools.", response.parsed_body["error"]
  end

  test "an agent bearer token does not stand in for a session" do
    sign_out

    webmcp_tool("list_items", {}, headers: { "Authorization" => "Bearer cursor-test-token" })

    assert_response :unauthorized
  end

  test "tool calls need the page's CSRF token" do
    with_forgery_protection do
      webmcp_tool("list_items", {})
      assert_response :unprocessable_content
      assert_match "CSRF", response.parsed_body["error"]

      webmcp_tool("list_items", {}, headers: { "X-CSRF-Token" => "forged" })
      assert_response :unprocessable_content

      get agents_path
      token = response.body[/<meta name="csrf-token" content="([^"]+)"/, 1]
      webmcp_tool("list_items", {}, headers: { "X-CSRF-Token" => token })
      assert_response :success
    end
  end

  test "list_items with filters returns the same payload as MCP" do
    arguments = { product: "cora", sentiment: [ "complaint" ] }
    webmcp = webmcp_tool("list_items", arguments)

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal tool_payload(mcp_tool("list_items", arguments)), webmcp
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ], webmcp["items"].pluck("id")
  end

  test "an invalid filter comes back as a 422 with the same text as the MCP tool error" do
    arguments = { sentiment: [ "furious" ] }
    assert_equal tool_error_text(mcp_tool("list_items", arguments)), webmcp_error("list_items", arguments)
    assert_match "is not a filter", webmcp_error("list_items", { mood: "grumpy" })
    assert_match "limit", webmcp_error("list_items", { limit: "many" })
  end

  test "get_item reads an item and reports an unknown one" do
    item = webmcp_tool("get_item", { item_id: items(:angry_slack).id })["item"]
    assert_equal true, item["messages"].first.dig("body", "untrusted")

    assert_equal "Item 0 was not found.", webmcp_error("get_item", { item_id: 0 })
  end

  test "list_anomalies answers with anomalies" do
    assert_equal [], webmcp_tool("list_anomalies", {})["anomalies"]
  end

  test "claim then report holds the claim with the person's browser agent and credits the person" do
    item = items(:angry_slack)

    claimed = assert_difference -> { Agent.count } => 1 do
      webmcp_tool("claim_item", { item_id: item.id })["item"]
    end
    browser = @user.reload.browser_agent
    assert_equal "Ana Every (WebMCP)", browser.name
    assert_equal browser.name, claimed["claimed_by"]
    assert_equal browser, item.reload.claimed_by_agent
    assert_not_nil browser.last_used_at

    reported = webmcp_tool("report_item", {
      item_id: item.id, summary: "Replied from the browser.", status: "handled"
    })["item"]

    assert_equal "handled", reported["status"]
    assert_equal({ "type" => "User", "name" => "Ana Every" }, reported["timeline"].find { |e| e["kind"] == "claimed" }["actor"])
    assert_equal({ "type" => "User", "name" => "Ana Every" }, reported["timeline"].find { |e| e["kind"] == "reported" }["actor"])
    assert_equal [ @user ], item.events.where(kind: %w[claimed reported]).map(&:actor).uniq
  end

  test "release_item gives back the person's own claim and credits the person" do
    item = items(:angry_slack)
    webmcp_tool("claim_item", { item_id: item.id })

    released = webmcp_tool("release_item", { item_id: item.id })["item"]

    assert_equal "new", released["status"]
    assert_equal @user, item.events.released.last.actor
  end

  test "the browser agent follows the same claim rules as MCP agents" do
    taken = items(:claimed_intercom)

    assert_equal "Item #{taken.id} is already claimed by Cursor.",
      webmcp_error("claim_item", { item_id: taken.id })
    assert_match "not claimed by Ana Every (WebMCP)",
      webmcp_error("release_item", { item_id: taken.id })
    assert_equal agents(:cursor), taken.reload.claimed_by_agent
  end

  test "revoking the browser agent stops the person's WebMCP writes" do
    Agent.browser_for(@user).revoke!

    assert_equal "The agent token was revoked.",
      webmcp_error("claim_item", { item_id: items(:angry_slack).id })
  end

  test "missing required arguments come back as a tool error" do
    assert_match "item_id", webmcp_error("claim_item", {})
  end

  test "an unknown tool is 404" do
    webmcp_tool("drop_tables", {})

    assert_response :not_found
    assert_equal "Tool drop_tables was not found.", response.parsed_body["error"]
  end

  test "a body that is not a JSON object is 400" do
    post webmcp_tool_path("list_items"), params: "[1]", headers: { "Content-Type" => "application/json" }
    assert_response :bad_request

    post webmcp_tool_path("list_items"), params: "{", headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
  end

  test "a broken tool is 500 without internals" do
    original = Mcp::Tools::ListItems.method(:call)
    Mcp::Tools::ListItems.define_singleton_method(:call) { |**| raise "database exploded" }

    webmcp_tool("list_items", {})

    assert_response :internal_server_error
    assert_equal "Internal error calling tool list_items", response.parsed_body["error"]
  ensure
    Mcp::Tools::ListItems.define_singleton_method(:call, original)
  end

  private

  def webmcp_tool(name, arguments, headers: {})
    post webmcp_tool_path(name), params: arguments.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers)
    response.parsed_body
  end

  def webmcp_error(name, arguments)
    body = webmcp_tool(name, arguments)
    assert_response :unprocessable_content
    body["error"]
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
