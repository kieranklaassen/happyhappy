# frozen_string_literal: true

# Helpers for the tools that act on one feed item.
module ItemTool
  ITEM_ID = { type: "integer", description: "The item id, as returned by list_items." }.freeze

  private

  def item
    @item ||= Item.find_by(id: arguments[:item_id]) or raise ApplicationTool::Error, "Item #{arguments[:item_id]} was not found."
  end

  def item_result(result)
    raise ApplicationTool::Error, result.message if result.failure?

    { item: Mcp::ItemPayload.detail(result.item) }
  end
end
