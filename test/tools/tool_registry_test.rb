# frozen_string_literal: true

require "test_helper"

class ToolRegistryTest < ActionDispatch::IntegrationTest
  include McpHelper

  # WebMCP (Chrome) and MCP share this alphabet; a name outside it is rejected
  # at registration and would fail silently in the browser.
  TOOL_NAME = /\A[A-Za-z0-9_.\-]{1,128}\z/

  setup do
    host! "localhost"
    @user = users(:every_ana)
  end

  def mcp(method, params = nil)
    ToolRegistry.mcp_server(user: @user).handle({ jsonrpc: "2.0", id: 1, method:, params: }.compact)
  end

  test "every registered tool is an ApplicationTool with a valid, unique name and a description" do
    assert_equal %w[list_items get_item claim_item release_item report_item list_anomalies], ToolRegistry.tools.map(&:tool_name)
    ToolRegistry.tools.each do |tool|
      assert_operator tool, :<, ApplicationTool
      assert_match TOOL_NAME, tool.tool_name
      assert tool.description.present?, "#{tool.name} needs a description"
      assert_equal "object", tool.input_schema.to_h[:type]
    end
  end

  test "every ApplicationTool in app/tools is registered" do
    app_tools = Rails.root.join("app/tools").to_s
    Rails.autoloaders.main.eager_load_dir(app_tools)
    defined = ApplicationTool.descendants.select do |tool|
      tool.name && Object.const_source_location(tool.name)&.first.to_s.start_with?(app_tools)
    end
    assert_empty defined - ToolRegistry.tools, "add these to ToolRegistry::TOOLS"
  end

  test "the /mcp endpoint serves exactly the registry's tools" do
    tools = mcp_request("tools/list").dig("result", "tools")

    assert_equal ToolRegistry.tools.map(&:to_h).as_json, tools
  end

  test "the WebMCP manifest lists the same tools as MCP tools/list" do
    listed = mcp("tools/list")[:result][:tools].map { |tool| tool.slice(:name, :description, :inputSchema, :annotations) }
    assert_equal listed, ToolRegistry.manifest[:tools]
    assert_equal "/webmcp/tools", ToolRegistry.manifest[:endpoint]
  end

  test "manifest annotations mark only the read tools read-only" do
    annotations = ToolRegistry.manifest[:tools].to_h { |tool| [ tool[:name], tool[:annotations] ] }

    %w[list_items get_item list_anomalies].each { |name| assert_equal true, annotations[name][:readOnlyHint], name }
    %w[claim_item release_item report_item].each { |name| assert_not annotations[name][:readOnlyHint], name }
    assert_equal false, annotations["claim_item"][:destructiveHint]
  end

  test "list_items offers every ItemsQuery filter plus paging" do
    properties = ListItemsTool.input_schema.to_h[:properties].keys

    assert_equal ItemsQuery::FILTERS + %i[limit offset], properties
  end

  test "a filter added to ItemsQuery appears in the list_items schema" do
    list_filters = ItemsQuery::LIST_FILTERS + %i[author_role]
    scalar_filters = ItemsQuery::SCALAR_FILTERS + %i[actionable]
    stub_const(ItemsQuery, :LIST_FILTERS, list_filters) do
      stub_const(ItemsQuery, :FILTERS, list_filters + scalar_filters) do
        schema = ListItemsTool.send(:filter_schema)

        assert_equal "array", schema[:author_role][:anyOf].last[:type]
        assert_equal({ type: "string" }, schema[:actionable])
      end
    end
  end

  test "call returns the MCP tools/call result for the same arguments" do
    arguments = { product: "cora", sentiment: [ "complaint" ] }
    expected = mcp("tools/call", { name: "list_items", arguments: })[:result]

    assert_equal expected, ToolRegistry.call("list_items", arguments:, user: @user)
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ], expected[:structuredContent]["items"].pluck("id")
  end

  test "call runs a read tool without creating a browser agent" do
    assert_no_difference -> { Agent.count } do
      result = ToolRegistry.call("get_item", arguments: { item_id: items(:angry_slack).id }, user: @user)

      assert_not result[:isError]
    end
  end

  test "call validates arguments exactly as MCP does" do
    result = ToolRegistry.call("list_items", arguments: { limit: "many" }, user: @user)

    assert result[:isError]
    assert_match "limit", result[:content].first[:text]
    assert_equal tool_error_text(mcp_tool("list_items", { limit: "many" })), result[:content].first[:text]
  end

  test "call returns nil for an unknown tool" do
    assert_nil ToolRegistry.call("drop_tables", arguments: {}, user: @user)
  end

  test "a tool never runs without a user or an agent" do
    result = ToolRegistry.call("list_items", arguments: {}, user: nil)
    assert result[:isError]
    assert_match(/sign in/i, result[:content].first[:text])
  end
end
