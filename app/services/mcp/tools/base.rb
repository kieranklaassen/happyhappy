module Mcp
  module Tools
    # Shared helpers for happyhappy's MCP tools. The authenticated agent arrives in
    # `server_context[:agent]` (see Mcp::Server.build). Refusals come back as tool errors
    # (`isError: true`) whose text says why, so the agent can read and act on them.
    class Base < MCP::Tool
      ITEM_ID = { type: "integer", description: "The item id, as returned by list_items." }.freeze

      class << self
        # Whether results carry customer-written content (WebMCP's untrustedContentHint).
        def untrusted_content?
          true
        end

        private

        def agent(server_context)
          server_context[:agent]
        end

        def with_item(item_id)
          item = Item.find_by(id: item_id)
          item ? yield(item) : failure("Item #{item_id} was not found.")
        end

        def agent_result(result)
          result.success? ? success(item: ItemPayload.detail(result.item)) : failure(result.message)
        end

        def success(payload)
          MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], structured_content: payload.as_json)
        end

        def failure(message)
          MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
        end
      end
    end
  end
end
