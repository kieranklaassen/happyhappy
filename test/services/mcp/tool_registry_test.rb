require "test_helper"

class Mcp::ToolRegistryTest < ActionDispatch::IntegrationTest
  include McpHelper

  setup { host! "localhost" }

  test "MCP tools/list serves exactly the registry definitions" do
    tools = mcp_request("tools/list").dig("result", "tools")

    assert_equal Mcp::ToolRegistry.definitions.as_json, tools
  end

  test "the WebMCP manifest carries the same names, descriptions, and input schemas as MCP" do
    mcp = Mcp::ToolRegistry.definitions.map do |tool|
      schema = tool[:inputSchema]
      [ tool[:name], tool[:description], schema[:properties] || {}, (schema[:required] || []).map(&:to_s) ]
    end
    webmcp = Mcp::ToolRegistry.webmcp_tools("https://example.test")[:tools].map do |tool|
      schema = tool[:input_schema]
      [ tool[:name], tool[:description], schema[:properties], schema[:required] ]
    end

    assert_equal mcp, webmcp
  end

  test "each WebMCP tool POSTs its declared arguments to its own endpoint without an agent name" do
    tools = Mcp::ToolRegistry.webmcp_tools("https://example.test")[:tools].index_by { |tool| tool[:name] }
    claim = tools.fetch("claim_item")

    assert_equal({ type: "object", properties: claim[:input_schema][:properties], required: [ "item_id" ],
      additionalProperties: false }, claim[:input_schema])
    assert_equal({ method: "POST", url: "https://example.test/webmcp/tools/claim_item", path_params: [],
      body_params: [ "item_id" ], agent_identity: "omit" }, claim[:request])
    assert_equal "request", claim[:kind]
    assert_equal false, claim[:include_viewer_context]
    assert_equal ItemsQuery::FILTERS.map(&:to_s) + %w[limit offset], tools.fetch("list_items")[:request][:body_params]
  end

  test "WebMCP annotations follow the MCP read-only hint and mark customer content untrusted" do
    annotations = Mcp::ToolRegistry.webmcp_tools("https://example.test")[:tools].to_h { |tool| [ tool[:name], tool[:annotations] ] }

    assert_equal({ read_only_hint: true, untrusted_content_hint: true }, annotations["list_items"])
    assert_equal({ read_only_hint: true, untrusted_content_hint: true }, annotations["get_item"])
    assert_equal({ read_only_hint: false, untrusted_content_hint: true }, annotations["claim_item"])
    assert_equal({ read_only_hint: true, untrusted_content_hint: false }, annotations["list_anomalies"])
  end

  test "list_items offers every ItemsQuery filter plus paging" do
    properties = Mcp::ToolRegistry.find("list_items").input_schema_value.to_h[:properties].keys

    assert_equal ItemsQuery::FILTERS + %i[limit offset], properties
  end

  test "a filter added to ItemsQuery appears in the list_items schema" do
    list_filters = ItemsQuery::LIST_FILTERS + %i[author_role]
    scalar_filters = ItemsQuery::SCALAR_FILTERS + %i[actionable]
    stub_const(ItemsQuery, :LIST_FILTERS, list_filters) do
      stub_const(ItemsQuery, :FILTERS, list_filters + scalar_filters) do
        schema = Mcp::Tools::ListItems.send(:filter_schema)

        assert_equal "array", schema[:author_role][:anyOf].last[:type]
        assert_equal({ type: "string" }, schema[:actionable])
      end
    end
  end

  test "call runs a read tool without creating a browser agent" do
    assert_no_difference -> { Agent.count } do
      result = Mcp::ToolRegistry.call("list_items", { product: "cora", sentiment: [ "complaint" ] }, user: users(:every_ana))

      assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ], result[:structuredContent]["items"].pluck("id")
    end
  end

  test "call validates arguments exactly as MCP does" do
    result = Mcp::ToolRegistry.call("list_items", { limit: "many" }, user: users(:every_ana))

    assert result[:isError]
    assert_match "limit", result[:content].first[:text]
  end

  test "call refuses an unknown tool" do
    assert_raises(Mcp::ToolRegistry::UnknownTool) { Mcp::ToolRegistry.call("drop_tables", {}, user: users(:every_ana)) }
  end
end
