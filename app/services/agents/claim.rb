module Agents
  # Gives an unclaimed new item to one agent. The claim is a single conditional
  # UPDATE, so of two agents racing for the same item exactly one wins; the other
  # gets :taken. Claiming an item the agent already holds succeeds without a new event.
  #
  #   Agents::Claim.call(agent: agent, item: item) # => Result with #item, or :revoked,
  #                                                #    :taken, :not_claimable
  class Claim
    def self.call(...)
      new(...).call
    end

    def initialize(agent:, item:)
      @agent = agent
      @item = item
    end

    def call
      return Result.failure(:revoked, "The agent token was revoked.") if @agent.revoked?

      won = Item.transaction do
        now = Time.current
        claimed = Item.where(id: @item.id, claimed_by_agent_id: nil, status: "new").update_all(
          claimed_by_agent_id: @agent.id, claimed_at: now, status: "claimed",
          status_changed_at: now, overdue: false, updated_at: now
        )
        @item.record_event!(:claimed, actor: @agent, from: "new", to: "claimed") if claimed == 1
        claimed == 1
      end
      @item.reload

      if won || @item.claimed_by_agent_id == @agent.id
        Result.success(@item)
      elsif @item.claimed_by_agent_id || @item.status_new?
        holder = @item.claimed_by_agent&.name || "another agent"
        Result.failure(:taken, "Item #{@item.id} is already claimed by #{holder}.")
      else
        Result.failure(:not_claimable,
          "Item #{@item.id} is #{@item.status.humanize(capitalize: false)}; only new items can be claimed.")
      end
    end
  end
end
