module Agents
  # Returns a claimed or in-progress item to new with no holder. An agent may only
  # release its own claim; a person (a User actor) may reassign any agent's claim.
  #
  #   Agents::Release.call(item: item, actor: agent) # => Result with #item, or :revoked, :not_holder
  #   Agents::Release.call(item: item, actor: user)  # => Result with #item, or :not_holder
  class Release
    def self.call(...)
      new(...).call
    end

    def initialize(item:, actor:)
      raise ArgumentError, "actor must be an Agent or a User" unless actor.is_a?(Agent) || actor.is_a?(User)

      @item = item
      @actor = actor
    end

    def call
      return Result.failure(:revoked, "The agent token was revoked.") if agent? && @actor.revoked?

      @item.reload
      holder_id = @item.claimed_by_agent_id
      from = @item.status
      return not_holder unless holder_id && Item::HELD_STATUSES.include?(from) && (!agent? || holder_id == @actor.id)

      released = Item.transaction do
        now = Time.current
        updated = Item.where(id: @item.id, claimed_by_agent_id: holder_id, status: from).update_all(
          claimed_by_agent_id: nil, claimed_at: nil, status: "new",
          status_changed_at: now, overdue: false, updated_at: now
        )
        if updated == 1
          @item.record_event!(agent? ? :released : :reassigned, actor: agent? ? @actor.event_actor : @actor,
            from: from, to: "new", agent_id: holder_id)
        end
        updated == 1
      end
      @item.reload

      released ? Result.success(@item) : not_holder
    end

    private

    def agent?
      @actor.is_a?(Agent)
    end

    def not_holder
      message = agent? ? "Item #{@item.id} is not claimed by #{@actor.name}." : "Item #{@item.id} is not claimed."
      Result.failure(:not_holder, message)
    end
  end
end
