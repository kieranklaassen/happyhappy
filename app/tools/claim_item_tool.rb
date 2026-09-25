# frozen_string_literal: true

class ClaimItemTool < ApplicationTool
  include ItemTool

  tool_name "claim_item"
  description <<~TEXT.squish
    Claim a new item so no other agent works it. The item stays yours until you report it handled or
    release it. Claiming an item another agent holds fails and names the holder.
  TEXT
  input_schema(properties: { item_id: ITEM_ID }, required: [ "item_id" ])
  annotations(destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def call
    item_result(Agents::Claim.call(item:, agent:))
  end
end
