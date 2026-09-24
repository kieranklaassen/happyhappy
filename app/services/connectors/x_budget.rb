module Connectors
  # Monthly spend guard for one X source (KTD16). X does not report cost, so
  # spend is estimated from pay-per-use prices: every post read, and every
  # expanded author counted as a user read until billing confirms otherwise.
  class XBudget
    POST_COST = BigDecimal("0.005")
    USER_COST = BigDecimal("0.010")
    WORST_CASE_PER_POST = POST_COST + USER_COST
    # Recent search rejects max_results outside 10..100.
    MIN_RESULTS = 10
    MAX_RESULTS = 100

    def self.cost(posts:, users:)
      posts * POST_COST + users * USER_COST
    end

    def initialize(source, now: Time.current)
      @source = source
      @month_key = now.strftime("%Y-%m")
    end

    # Starts a new month's running total and lifts a budget pause when the
    # month key changes.
    def roll_month!
      return if @source.month_key == @month_key

      @source.update!(month_key: @month_key, month_spend: 0,
        status: @source.paused_for_budget? ? :active : @source.status)
    end

    def remaining
      [ (@source.monthly_limit || 0) - @source.month_spend, 0 ].max
    end

    # The largest page whose worst case still fits the limit, or nil when not
    # even the smallest page fits.
    def affordable_max_results
      results = [ (remaining / WORST_CASE_PER_POST).floor, MAX_RESULTS ].min
      results if results >= MIN_RESULTS
    end

    # Pauses for budget when no page fits and resumes a budget-paused source
    # once the limit is raised. Returns whether a call may run.
    def permit!
      if affordable_max_results
        @source.update!(status: :active) if @source.paused_for_budget?
        true
      else
        @source.update!(status: :paused_for_budget) unless @source.paused_for_budget?
        false
      end
    end

    def record_spend!(posts:, users:)
      @source.update!(month_spend: @source.month_spend + self.class.cost(posts: posts, users: users))
    end
  end
end
