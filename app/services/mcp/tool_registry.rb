module Mcp
  # The one list of happyhappy's tools. The MCP server serves it to agents with a token, and signed-in pages
  # receive the same tools as a WebMCP manifest (the Thinkroom manifest shape, see app/frontend/lib/webmcp.ts)
  # and run them through `call`, so both surfaces share names, descriptions, input schemas, and implementations.
  #
  #   Mcp::ToolRegistry.definitions                                  # => what MCP tools/list returns
  #   Mcp::ToolRegistry.webmcp_tools("https://happyhappy.example")   # => { tools: [...] } WebMCP manifest
  #   Mcp::ToolRegistry.call("list_items", { product: "cora" }, user:) # => MCP tools/call result Hash
  module ToolRegistry
    class UnknownTool < StandardError; end
    class Failed < StandardError; end

    TOOLS = [
      Tools::ListItems, Tools::GetItem, Tools::ClaimItem, Tools::ReleaseItem, Tools::ReportItem, Tools::ListAnomalies
    ].freeze

    module_function

    def definitions
      TOOLS.map(&:to_h)
    end

    # Every tool is a "request" tool that POSTs its arguments to WebmcpToolsController. agent_identity is
    # "omit" because the session, not an agent_name argument, decides who acts (Agent.browser_for).
    def webmcp_tools(base_url)
      { tools: TOOLS.map { |tool| webmcp_tool(tool, base_url) } }
    end

    def webmcp_tool(tool, base_url)
      schema = tool.input_schema_value.to_h
      properties = schema.fetch(:properties, {})
      {
        name: tool.name_value,
        description: tool.description_value,
        input_schema: {
          type: "object", properties: properties, required: schema.fetch(:required, []).map(&:to_s),
          additionalProperties: false
        },
        annotations: { read_only_hint: read_only?(tool), untrusted_content_hint: tool.untrusted_content? },
        kind: "request",
        request: {
          method: "POST", url: "#{base_url}/webmcp/tools/#{tool.name_value}", path_params: [],
          body_params: properties.keys.map(&:to_s), agent_identity: "omit"
        },
        include_viewer_context: false
      }
    end

    def find(name)
      TOOLS.find { |tool| tool.name_value == name.to_s }
    end

    def read_only?(tool)
      tool.annotations_value&.read_only_hint || false
    end

    # Runs one tool for a signed-in person through the MCP server's own tools/call handling, so argument
    # validation and results match MCP. Write tools act as the person's browser agent (Agent.browser_for).
    # Tool refusals come back as results with isError; Failed means the tool itself broke.
    def call(name, arguments, user:)
      tool = find(name) or raise UnknownTool, "Tool #{name} was not found."
      agent = Agent.browser_for(user).tap { |browser| browser.touch(:last_used_at) } unless read_only?(tool)

      response = Server.build(agent: agent).handle(
        { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: tool.name_value, arguments: arguments } }
      )
      response.fetch(:result) { raise Failed, response.dig(:error, :data) || response.dig(:error, :message) }
    end
  end
end
