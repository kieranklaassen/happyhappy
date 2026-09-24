module Mcp
  module Tools
    class ReportItem < Base
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

      class << self
        def call(item_id:, summary:, status:, server_context:, link: nil)
          with_item(item_id) do |item|
            agent_result(Agents::Report.call(agent: agent(server_context), item: item,
              summary: summary, status: status, link: link))
          end
        end
      end
    end
  end
end
