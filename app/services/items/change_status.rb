module Items
  # Changes an item's status on a person's behalf.
  #
  #   Items::ChangeStatus.call(item:, status: "dismissed", actor: Current.user)  # => true, or false if unchanged
  #
  # People can reopen, handle, or dismiss an item; claimed and in progress come only from agents. Moving a
  # claimed item releases the agent's claim (R25) and clears its overdue flag. Raises Invalid otherwise.
  class ChangeStatus
    class Invalid < ArgumentError; end

    STATUSES = %w[new handled dismissed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(item:, status:, actor:)
      @item = item
      @status = status.to_s
      @actor = actor
    end

    def call
      raise Invalid, "#{@status.inspect} is not a status you can set" unless STATUSES.include?(@status)
      return false if @item.status == @status

      @item.transaction do
        agent = @item.claimed_by_agent
        @item.update!(claimed_by_agent: nil, claimed_at: nil, overdue: false) if agent
        @item.change_status!(@status, actor: @actor, **{ released_agent: agent&.name }.compact)
      end
    end
  end
end
