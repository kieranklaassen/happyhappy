require "test_helper"

class Connectors::XBudgetTest < ActiveSupport::TestCase
  setup do
    @source = sources(:x_mentions)
  end

  test "cost counts $0.005 per post and $0.010 per expanded user" do
    assert_equal BigDecimal("0.035"), Connectors::XBudget.cost(posts: 3, users: 2)
    assert_equal BigDecimal("1.5"), Connectors::XBudget.cost(posts: 100, users: 100)
  end

  test "the page size is the largest whose worst case fits the remaining budget" do
    assert_equal 100, budget.affordable_max_results

    @source.update!(month_spend: 49)
    assert_equal 66, budget.affordable_max_results

    @source.update!(month_spend: BigDecimal("49.85"))
    assert_equal 10, budget.affordable_max_results

    @source.update!(month_spend: BigDecimal("49.9"))
    assert_nil budget.affordable_max_results
  end

  test "permit! pauses for budget when no page fits, and resumes once the limit is raised" do
    @source.update!(month_spend: 50)

    assert_not budget.permit!
    assert @source.reload.paused_for_budget?

    @source.update!(monthly_limit: 60)
    assert budget.permit!
    assert @source.reload.active?
  end

  test "a source without a monthly limit never polls" do
    @source.update!(monthly_limit: nil, month_spend: 0)

    assert_not budget.permit!
    assert @source.reload.paused_for_budget?
  end

  test "a new month key resets spend and lifts a budget pause" do
    source = sources(:x_budget_paused)
    next_month = 1.month.from_now

    Connectors::XBudget.new(source, now: next_month).roll_month!

    source.reload
    assert_equal next_month.strftime("%Y-%m"), source.month_key
    assert_equal 0, source.month_spend
    assert source.active?
  end

  test "a new month keeps a manual pause" do
    @source.update!(status: :paused)

    Connectors::XBudget.new(@source, now: 1.month.from_now).roll_month!

    assert_equal 0, @source.reload.month_spend
    assert @source.paused?
  end

  test "the same month leaves spend alone" do
    budget.roll_month!

    assert_equal BigDecimal("12.5"), @source.reload.month_spend
  end

  test "record_spend! adds the actual cost to the running total" do
    budget.record_spend!(posts: 10, users: 4)

    assert_equal BigDecimal("12.59"), @source.reload.month_spend
  end

  private

  def budget
    Connectors::XBudget.new(@source)
  end
end
