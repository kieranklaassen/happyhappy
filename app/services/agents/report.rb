module Agents
  # Records what an agent did on an item it holds: a summary, an optional link, and
  # the new status (in progress or handled). Reporting clears the overdue flag and
  # restarts the report-back window; reporting handled also releases the claim.
  #
  #   Agents::Report.call(agent:, item:, summary: "Refunded", status: "handled", link: nil)
  #   # => Result with #item, or :revoked, :not_holder, :invalid
  class Report
    STATUSES = %w[in_progress handled].freeze
    HOLDING_STATUSES = %w[claimed in_progress].freeze
    SUMMARY_MAX = 5_000
    LINK_MAX = 2_000

    def self.call(...)
      new(...).call
    end

    def initialize(agent:, item:, summary:, status:, link: nil)
      @agent = agent
      @item = item
      @summary = summary.to_s.strip
      @status = status.to_s
      @link = link.to_s.strip.presence
    end

    def call
      return Result.failure(:revoked, "The agent token was revoked.") if @agent.revoked?
      if (problem = validation_problem)
        return Result.failure(:invalid, problem)
      end

      @item.reload
      from = @item.status
      return not_holder unless @item.claimed_by_agent_id == @agent.id && HOLDING_STATUSES.include?(from)

      reported = Item.transaction do
        updated = Item.where(id: @item.id, claimed_by_agent_id: @agent.id, status: from).update_all(changes(from))
        if updated == 1
          @item.record_event!(:reported, actor: @agent, summary: @summary, link: @link, status: @status, from: from)
        end
        updated == 1
      end
      @item.reload

      reported ? Result.success(@item) : not_holder
    end

    private

    def validation_problem
      return "Status must be one of: #{STATUSES.join(', ')}." unless STATUSES.include?(@status)
      return "A summary of what was done is required." if @summary.empty?
      return "The summary must be at most #{SUMMARY_MAX} characters." if @summary.length > SUMMARY_MAX
      "The link must be an http or https URL." if @link && !web_url?(@link)
    end

    def web_url?(link)
      return false if link.length > LINK_MAX

      uri = URI.parse(link)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def changes(from)
      now = Time.current
      changes = { last_reported_at: now, overdue: false, updated_at: now }
      changes.merge!(status: @status, status_changed_at: now) unless from == @status
      changes.merge!(claimed_by_agent_id: nil, claimed_at: nil) if @status == "handled"
      changes
    end

    def not_holder
      Result.failure(:not_holder, "Item #{@item.id} is not claimed by #{@agent.name}.")
    end
  end
end
