require "test_helper"

class OverdueSweepJobTest < ActiveJob::TestCase
  setup do
    @item = items(:claimed_intercom)
    assert_equal 240, Setting.current.report_back_window_minutes
  end

  test "covers AE6: an item claimed five hours ago with a four-hour window is flagged overdue" do
    @item.update!(claimed_at: 5.hours.ago, last_reported_at: nil)

    OverdueSweepJob.perform_now

    assert @item.reload.overdue?
    event = @item.events.last
    assert_equal "overdue", event.kind
    assert_nil event.actor
    assert_equal agents(:cursor).id, event.data["agent_id"]
  end

  test "an item that got a progress report two hours ago is not overdue, even if claimed six hours ago" do
    @item.update!(status: "in_progress", claimed_at: 6.hours.ago, last_reported_at: 2.hours.ago)

    OverdueSweepJob.perform_now

    assert_not @item.reload.overdue?
  end

  test "an in-progress item whose last report is older than the window is flagged" do
    @item.update!(status: "in_progress", claimed_at: 7.hours.ago, last_reported_at: 5.hours.ago)

    OverdueSweepJob.perform_now

    assert @item.reload.overdue?
  end

  test "an item claimed three hours ago is not overdue" do
    @item.update!(claimed_at: 3.hours.ago)

    OverdueSweepJob.perform_now

    assert_not @item.reload.overdue?
  end

  test "the window comes from settings" do
    Setting.current.update!(report_back_window_minutes: 60)
    @item.update!(claimed_at: 90.minutes.ago)

    OverdueSweepJob.perform_now

    assert @item.reload.overdue?
  end

  test "sweeping twice flags once" do
    @item.update!(claimed_at: 5.hours.ago)

    OverdueSweepJob.perform_now
    assert_no_difference -> { ItemEvent.count } do
      OverdueSweepJob.perform_now
    end
  end

  test "unclaimed and resolved items are never flagged" do
    items(:handled_email).update!(claimed_at: 5.days.ago)

    OverdueSweepJob.perform_now

    assert_equal [ @item.id ], Item.where(overdue: true).pluck(:id)
  end

  test "a report after the flag clears it" do
    @item.update!(claimed_at: 5.hours.ago)
    OverdueSweepJob.perform_now

    Agents::Report.call(agent: agents(:cursor), item: @item, summary: "Working on it", status: "in_progress")

    assert_not @item.reload.overdue?
    OverdueSweepJob.perform_now
    assert_not @item.reload.overdue?
  end
end
