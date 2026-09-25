# frozen_string_literal: true

require "test_helper"

class WebmcpToolsControllerTest < ActionDispatch::IntegrationTest
  include McpHelper
  include TrufflerHelper
  include ActiveJob::TestHelper

  setup do
    host! "localhost"
    @user = users(:every_ana)
    WebmcpToolsController::RATE_LIMIT_STORE.clear
  end

  def call_tool(name, body = { arguments: {} }, headers: {})
    post webmcp_tool_path(name), params: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers)
  end

  # The MCP CallToolResult the endpoint returned for a signed-in call.
  def webmcp_tool(name, arguments)
    call_tool(name, { arguments: })
    assert_response :success
    response.parsed_body["result"]
  end

  test "the route path matches ToolRegistry::ENDPOINT" do
    assert_equal "#{ToolRegistry::ENDPOINT}/list_items", webmcp_tool_path("list_items")
  end

  test "without a session it answers 401 JSON and changes nothing" do
    assert_no_changes -> { items(:angry_slack).reload.status } do
      call_tool("claim_item", { arguments: { item_id: items(:angry_slack).id } })
    end

    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    assert_match(/sign in/i, response.parsed_body["error"])
  end

  test "an agent bearer token does not stand in for a session" do
    call_tool("list_items", headers: { "Authorization" => "Bearer cursor-test-token" })

    assert_response :unauthorized
  end

  test "returns exactly what MCP returns for list_items with filters" do
    sign_in_as @user
    arguments = { product: "cora", sentiment: [ "complaint" ] }

    result = webmcp_tool("list_items", arguments)

    assert_equal mcp_tool("list_items", arguments), result
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ], tool_payload(result)["items"].pluck("id")
  end

  test "returns exactly what MCP returns for search_items, with customer text marked untrusted" do
    sign_in_as @user
    index_items_for_search!
    Truffler.config.client.answer("intent__product", "filter").answer("option__product", "cora")
    arguments = { query: "cora", status: [ "new", "claimed" ] }

    result = perform_enqueued_jobs(only: Truffler::Jobs::EncodeQueryJob) { webmcp_tool("search_items", arguments) }
    via_mcp = perform_enqueued_jobs(only: Truffler::Jobs::EncodeQueryJob) { mcp_tool("search_items", arguments) }

    assert_equal via_mcp, result
    payload = tool_payload(result)
    assert_equal [ "product:cora" ], payload["chips"].pluck("key")
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ].sort, payload["items"].pluck("id").sort
    assert payload["items"].all? { |item| item.dig("excerpt", "untrusted") && item.dig("author", "untrusted") }
  end

  test "an invalid filter is the same isError result as MCP" do
    sign_in_as @user

    [ { sentiment: [ "furious" ] }, { mood: "grumpy" }, { limit: "many" } ].each do |arguments|
      assert_equal mcp_tool("list_items", arguments), webmcp_tool("list_items", arguments), arguments.inspect
    end
    assert_match "sentiment", tool_error_text(webmcp_tool("list_items", { sentiment: [ "furious" ] }))
    assert_match "is not a filter", tool_error_text(webmcp_tool("list_items", { mood: "grumpy" }))
    assert_match "limit", tool_error_text(webmcp_tool("list_items", { limit: "many" }))
  end

  test "get_item reads an item and reports an unknown one" do
    sign_in_as @user

    item = tool_payload(webmcp_tool("get_item", { item_id: items(:angry_slack).id }))["item"]
    assert_equal true, item["messages"].first.dig("body", "untrusted")
    assert_equal "Item 0 was not found.", tool_error_text(webmcp_tool("get_item", { item_id: 0 }))
  end

  test "list_anomalies answers with anomalies" do
    sign_in_as @user

    assert_equal [], tool_payload(webmcp_tool("list_anomalies", {}))["anomalies"]
  end

  test "claim then report holds the claim with the person's browser agent and credits the person" do
    sign_in_as @user
    item = items(:angry_slack)

    claimed = assert_difference -> { Agent.count } => 1 do
      tool_payload(webmcp_tool("claim_item", { item_id: item.id }))["item"]
    end
    browser = @user.reload.browser_agent
    assert_equal "Ana Every (WebMCP)", browser.name
    assert_equal browser.name, claimed["claimed_by"]
    assert_equal browser, item.reload.claimed_by_agent
    assert_not_nil browser.last_used_at

    reported = tool_payload(webmcp_tool("report_item", {
      item_id: item.id, summary: "Replied from the browser.", status: "handled"
    }))["item"]

    assert_equal "handled", reported["status"]
    assert_equal({ "type" => "User", "name" => "Ana Every" }, reported["timeline"].find { |e| e["kind"] == "claimed" }["actor"])
    assert_equal({ "type" => "User", "name" => "Ana Every" }, reported["timeline"].find { |e| e["kind"] == "reported" }["actor"])
    assert_equal [ @user ], item.events.where(kind: %w[claimed reported]).map(&:actor).uniq
  end

  test "release_item gives back the person's own claim and credits the person" do
    sign_in_as @user
    item = items(:angry_slack)
    webmcp_tool("claim_item", { item_id: item.id })

    released = tool_payload(webmcp_tool("release_item", { item_id: item.id }))["item"]

    assert_equal "new", released["status"]
    assert_equal @user, item.events.released.last.actor
  end

  test "the browser agent follows the same claim rules as MCP agents" do
    sign_in_as @user
    taken = items(:claimed_intercom)

    assert_equal "Item #{taken.id} is already claimed by Cursor.",
      tool_error_text(webmcp_tool("claim_item", { item_id: taken.id }))
    assert_match "not claimed by Ana Every (WebMCP)",
      tool_error_text(webmcp_tool("release_item", { item_id: taken.id }))
    assert_equal agents(:cursor), taken.reload.claimed_by_agent
  end

  test "revoking the browser agent stops the person's WebMCP writes" do
    sign_in_as @user
    Agent.browser_for(@user).revoke!

    assert_equal "The agent token was revoked.",
      tool_error_text(webmcp_tool("claim_item", { item_id: items(:angry_slack).id }))
  end

  test "an argument that fails the input schema is an isError result" do
    sign_in_as @user

    assert_match "item_id", tool_error_text(webmcp_tool("claim_item", {}))
  end

  test "an unknown tool is 404" do
    sign_in_as @user
    call_tool("drop_tables")

    assert_response :not_found
    assert_match(/drop_tables/, response.parsed_body["error"])
  end

  test "a malformed body is 400" do
    sign_in_as @user

    call_tool("list_items", "not json")
    assert_response :bad_request

    call_tool("list_items", { arguments: [ 1, 2 ] })
    assert_response :bad_request
  end

  test "a broken tool is an isError result without internals" do
    sign_in_as @user
    original = ListItemsTool.instance_method(:call)
    ListItemsTool.define_method(:call) { raise "database exploded" }

    result = webmcp_tool("list_items", {})

    assert result["isError"]
    assert_no_match "database exploded", result.to_json
  ensure
    ListItemsTool.define_method(:call, original)
  end

  test "tool calls are rate limited per user" do
    sign_in_as @user
    60.times { call_tool("list_anomalies") }
    assert_response :success

    call_tool("list_anomalies")
    assert_response :too_many_requests
    assert_equal "application/json", response.media_type
  end

  class CsrfTest < ActionDispatch::IntegrationTest
    setup do
      @forgery_protection = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      WebmcpToolsController::RATE_LIMIT_STORE.clear
      host! "localhost"
      sign_in_as(users(:every_ana))
    end

    teardown do
      ActionController::Base.allow_forgery_protection = @forgery_protection
    end

    def post_tool(headers = {})
      post webmcp_tool_path("list_anomalies"), params: { arguments: {} }.to_json,
        headers: { "Content-Type" => "application/json" }.merge(headers)
    end

    test "rejects a session call without a CSRF token as 422 JSON" do
      post_tool

      assert_response :unprocessable_content
      assert_match(/csrf/i, response.parsed_body["error"])
    end

    test "without a session the answer is still 401, checked before the token" do
      sign_out
      post_tool

      assert_response :unauthorized
    end

    test "rejects a forged token" do
      post_tool("X-CSRF-Token" => "forged")

      assert_response :unprocessable_content
    end

    test "accepts the token Inertia hands the page in the XSRF-TOKEN cookie" do
      get agents_path
      token = cookies["XSRF-TOKEN"]
      assert token.present?, "Inertia should set the XSRF-TOKEN cookie"

      post_tool("X-CSRF-Token" => CGI.unescape(token))

      assert_response :success
      assert_equal false, response.parsed_body.dig("result", "isError")
    end

    test "accepts the page's csrf-token meta" do
      get agents_path
      token = response.body[/<meta name="csrf-token" content="([^"]+)"/, 1]

      post_tool("X-CSRF-Token" => token)

      assert_response :success
      assert_equal false, response.parsed_body.dig("result", "isError")
    end
  end
end
