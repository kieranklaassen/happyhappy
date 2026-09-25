require "test_helper"

class ItemStatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:every_ana)
    sign_in_as @user
  end

  test "requires sign in" do
    sign_out
    patch item_status_path(items(:angry_slack)), params: { status: "dismissed" }

    assert_redirected_to new_session_path
    assert items(:angry_slack).reload.status_new?
  end

  test "a status change to dismissed writes a status event" do
    item = items(:angry_slack)

    assert_difference -> { item.events.status_changed.count } => 1 do
      patch item_status_path(item), params: { status: "dismissed" }
    end

    assert_redirected_to item_path(item)
    assert_equal "Marked dismissed.", flash[:notice]
    assert item.reload.status_dismissed?
    event = item.events.last
    assert_equal @user, event.actor
    assert_equal({ "from" => "new", "to" => "dismissed" }, event.data)
  end

  test "reopening a claimed item releases the agent" do
    item = items(:claimed_intercom)

    patch item_status_path(item), params: { status: "new" }

    assert item.reload.status_new?
    assert_nil item.claimed_by_agent
  end

  test "an agent-only status is refused with an alert" do
    item = items(:angry_slack)

    patch item_status_path(item), params: { status: "claimed" }

    assert_redirected_to item_path(item)
    assert_match "not a status you can set", flash[:alert]
    assert item.reload.status_new?
  end
end
