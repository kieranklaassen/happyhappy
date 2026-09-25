require "test_helper"

class Items::ChangeStatusTest < ActiveSupport::TestCase
  setup do
    @user = users(:every_ana)
  end

  test "dismissing a new item writes a status event with the user" do
    item = items(:angry_slack)

    assert Items::ChangeStatus.call(item: item, status: "dismissed", actor: @user)

    assert item.reload.status_dismissed?
    event = item.events.last
    assert event.status_changed?
    assert_equal @user, event.actor
    assert_equal({ "from" => "new", "to" => "dismissed" }, event.data)
  end

  test "moving a claimed item releases the agent's claim and clears overdue" do
    item = items(:claimed_intercom)
    item.update!(overdue: true)

    Items::ChangeStatus.call(item: item, status: "new", actor: @user)

    item.reload
    assert item.status_new?
    assert_nil item.claimed_by_agent
    assert_nil item.claimed_at
    refute item.overdue
    assert_equal({ "from" => "claimed", "to" => "new", "released_agent" => "Cursor" }, item.events.last.data)
  end

  test "the same status is a no-op" do
    item = items(:angry_slack)

    assert_no_difference -> { item.events.count } do
      refute Items::ChangeStatus.call(item: item, status: "new", actor: @user)
    end
  end

  test "people cannot set claimed or in progress, which belong to agents" do
    %w[claimed in_progress open].each do |status|
      assert_raises(Items::ChangeStatus::Invalid) do
        Items::ChangeStatus.call(item: items(:angry_slack), status: status, actor: @user)
      end
    end
    assert items(:angry_slack).reload.status_new?
  end
end
