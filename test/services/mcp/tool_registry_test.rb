require "test_helper"

class Mcp::ToolRegistryTest < ActionDispatch::IntegrationTest
  include McpHelper

  setup { host! "localhost" }

  test "MCP tools/list serves exactly the registry definitions" do
    tools = mcp_request("tools/list").dig("result", "tools")

    assert_equal Mcp::ToolRegistry.definitions.as_json, tools
  end

  test "WebMCP definitions carry the same names, titles, descriptions, and input schemas" do
    mcp = Mcp::ToolRegistry.definitions.map { |tool| tool.slice(:name, :title, :description, :inputSchema) }
    webmcp = Mcp::ToolRegistry.webmcp_definitions.map { |tool| tool.except(:annotations) }

    assert_equal mcp, webmcp
  end

  test "WebMCP annotations follow the MCP read-only hint and mark customer content untrusted" do
    annotations = Mcp::ToolRegistry.webmcp_definitions.to_h { |tool| [ tool[:name], tool[:annotations] ] }

    assert_equal({ readOnlyHint: true, untrustedContentHint: true }, annotations["list_items"])
    assert_equal({ readOnlyHint: true, untrustedContentHint: true }, annotations["get_item"])
    assert_equal({ readOnlyHint: false, untrustedContentHint: true }, annotations["claim_item"])
    assert_equal({ readOnlyHint: true, untrustedContentHint: false }, annotations["list_anomalies"])
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
