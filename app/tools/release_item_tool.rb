# frozen_string_literal: true

class ReleaseItemTool < ApplicationTool
  include ItemTool

  tool_name "release_item"
  description "Give back an item you claimed without handling it. It returns to new so someone else can take it."
  input_schema(properties: { item_id: ITEM_ID }, required: [ "item_id" ])
  annotations(destructive_hint: false, open_world_hint: false)

  def call
    item_result(Agents::Release.call(item:, actor: agent))
  end
end
