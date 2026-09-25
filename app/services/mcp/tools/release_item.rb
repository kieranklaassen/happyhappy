module Mcp
  module Tools
    class ReleaseItem < Base
      tool_name "release_item"
      description "Give back an item you claimed without handling it. It returns to new so someone else can take it."
      input_schema(properties: { item_id: ITEM_ID }, required: [ "item_id" ])
      annotations(destructive_hint: false, open_world_hint: false)

      class << self
        def call(item_id:, server_context:)
          with_item(item_id) { |item| agent_result(Agents::Release.call(item: item, actor: agent(server_context))) }
        end
      end
    end
  end
end
