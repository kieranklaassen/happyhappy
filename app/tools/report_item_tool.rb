# frozen_string_literal: true

class ReportItemTool < ApplicationTool
  include ItemTool

  tool_name "report_item"
  description <<~TEXT.squish
    Report what you did on an item you claimed. Use status in_progress for a progress update, which keeps
    your claim and restarts the report-back window, or handled when you are done, which releases the claim.
    The report appears on the item's timeline.
  TEXT
  input_schema(
    properties: {
      item_id: ITEM_ID,
      summary: { type: "string", description: "What you did, in plain words." },
      status: { type: "string", enum: Agents::Report::STATUSES },
      link: { type: "string", description: "Optional http or https link to your work, such as a reply or ticket." }
    },
    required: %w[item_id summary status]
  )
  annotations(destructive_hint: false, open_world_hint: false)

  def call
    item_result(Agents::Report.call(item:, agent:, **arguments.slice(:summary, :status, :link)))
  end
end
