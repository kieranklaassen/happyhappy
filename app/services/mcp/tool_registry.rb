module Mcp
  # The one list of happyhappy's tools. The MCP server serves it to agents with a token, and signed-in pages
  # register the same definitions with WebMCP (document.modelContext) and run them through `call`, so both
  # surfaces share names, descriptions, input schemas, and implementations.
  #
  #   Mcp::ToolRegistry.definitions                                  # => what MCP tools/list returns
  #   Mcp::ToolRegistry.webmcp_definitions                           # => the same tools as WebMCP registrations
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

    def webmcp_definitions
      TOOLS.map do |tool|
        tool.to_h.slice(:name, :title, :description, :inputSchema).merge(
          annotations: { readOnlyHint: read_only?(tool), untrustedContentHint: tool.untrusted_content? }
        )
      end
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
