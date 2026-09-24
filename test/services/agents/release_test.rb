require "test_helper"

class Agents::ReleaseTest < ActiveSupport::TestCase
  setup do
    @item = items(:claimed_intercom)
    @cursor = agents(:cursor)
  end

  test "the holding agent releases its claim and the item returns to new" do
    @item.update!(overdue: true)

    result = Agents::Release.call(item: @item, actor: @cursor)

    assert result.success?
    item = result.item
    assert item.status_new?
    assert_nil item.claimed_by_agent
    assert_nil item.claimed_at
    assert_not item.overdue?
    event = item.events.last
    assert_equal "released", event.kind
    assert_equal @cursor, event.actor
    assert_equal @cursor.id, event.data["agent_id"]
  end

  test "agent B cannot release agent A's claim" do
    result = nil
    assert_no_difference -> { ItemEvent.count } do
      result = Agents::Release.call(item: @item, actor: agents(:baby_agent))
    end

    assert_equal :not_holder, result.error
    assert_equal @cursor, @item.reload.claimed_by_agent
  end

  test "a person reassigns an agent's claim and the item returns to new" do
    user = users(:one)

    result = Agents::Release.call(item: @item, actor: user)

    assert result.item.status_new?
    assert_nil result.item.claimed_by_agent
    event = result.item.events.last
    assert_equal "reassigned", event.kind
    assert_equal user, event.actor
    assert_equal @cursor.id, event.data["agent_id"]
  end

  test "an in-progress item can be released" do
    Agents::Report.call(agent: @cursor, item: @item, summary: "Working", status: "in_progress")

    assert Agents::Release.call(item: @item, actor: @cursor).item.status_new?
  end

  test "releasing an unclaimed item is refused" do
    assert_equal :not_holder, Agents::Release.call(item: items(:angry_slack), actor: users(:one)).error
  end

  test "a revoked agent cannot release" do
    @cursor.revoke!

    assert_equal :revoked, Agents::Release.call(item: @item, actor: @cursor).error
  end

  test "the actor must be an agent or a person" do
    assert_raises(ArgumentError) { Agents::Release.call(item: @item, actor: nil) }
  end
end
