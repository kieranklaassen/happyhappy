require "test_helper"

class Agents::ReportTest < ActiveSupport::TestCase
  setup do
    @item = items(:claimed_intercom)
    @cursor = agents(:cursor)
  end

  test "a report with status handled records the summary and link and releases the claim" do
    freeze_time

    result = report(summary: "Refunded the duplicate charge", link: "https://app.intercom.com/x/1", status: "handled")

    assert result.success?
    item = result.item
    assert item.status_handled?
    assert_nil item.claimed_by_agent
    assert_nil item.claimed_at
    assert_equal Time.current, item.last_reported_at
    assert_equal Time.current, item.status_changed_at
    event = item.events.last
    assert_equal "reported", event.kind
    assert_equal @cursor, event.actor
    assert_equal({ "summary" => "Refunded the duplicate charge", "link" => "https://app.intercom.com/x/1",
                   "status" => "handled", "from" => "claimed" }, event.data)
  end

  test "a progress report keeps the claim and moves the item to in progress" do
    result = report(status: "in_progress")

    assert result.item.status_in_progress?
    assert_equal @cursor, result.item.claimed_by_agent
  end

  test "a second progress report keeps the status change time" do
    report(status: "in_progress")
    changed_at = @item.reload.status_changed_at

    travel 1.hour do
      result = report(status: "in_progress", summary: "Still waiting on the customer")
      assert_equal changed_at, result.item.status_changed_at
      assert_equal Time.current, result.item.last_reported_at
    end
  end

  test "a report clears the overdue flag" do
    @item.update!(overdue: true)

    assert_not report(status: "in_progress").item.overdue?
  end

  test "agent B cannot report on agent A's claim" do
    result = nil
    assert_no_difference -> { ItemEvent.count } do
      result = report(agent: agents(:baby_agent), status: "handled")
    end

    assert_equal :not_holder, result.error
    assert @item.reload.status_claimed?
    assert_equal @cursor, @item.claimed_by_agent
  end

  test "an agent cannot report on an item nobody claimed" do
    assert_equal :not_holder, report(item: items(:angry_slack), status: "handled").error
  end

  test "a revoked agent cannot report" do
    @cursor.revoke!

    assert_equal :revoked, report(status: "handled").error
  end

  test "reports with a bad status, a blank summary, or a non-web link are invalid" do
    assert_equal :invalid, report(status: "dismissed").error
    assert_equal :invalid, report(status: "new").error
    assert_equal :invalid, report(summary: "  ", status: "handled").error
    assert_equal :invalid, report(link: "javascript:alert(1)", status: "handled").error
    assert_equal :invalid, report(link: "not a url", status: "handled").error
    assert @item.reload.status_claimed?
  end

  test "a blank link is stored as none" do
    assert_nil report(link: " ", status: "in_progress").item.events.last.data["link"]
  end

  private

  def report(agent: @cursor, item: @item, summary: "Looked into it", link: nil, status:)
    Agents::Report.call(agent: agent, item: item, summary: summary, link: link, status: status)
  end
end
