require "test_helper"

class Agents::ClaimTest < ActiveSupport::TestCase
  setup do
    @item = items(:angry_slack)
    @cursor = agents(:cursor)
    @baby = agents(:baby_agent)
  end

  test "agent A claims a new item and it shows as claimed by A" do
    freeze_time

    result = Agents::Claim.call(agent: @cursor, item: @item)

    assert result.success?
    item = result.item
    assert item.status_claimed?
    assert_equal @cursor, item.claimed_by_agent
    assert_equal Time.current, item.claimed_at
    assert_equal Time.current, item.status_changed_at
    event = item.events.last
    assert_equal "claimed", event.kind
    assert_equal @cursor, event.actor
  end

  test "covers AE7: agent B's claim on A's item fails with a taken error" do
    Agents::Claim.call(agent: @cursor, item: @item)

    result = nil
    assert_no_difference -> { ItemEvent.count } do
      result = Agents::Claim.call(agent: @baby, item: @item)
    end

    assert_equal :taken, result.error
    assert_match "Cursor", result.message
    assert_equal @cursor, @item.reload.claimed_by_agent
  end

  test "a claim made from a stale copy of the item still loses to the earlier claim" do
    stale = Item.find(@item.id)
    Agents::Claim.call(agent: @cursor, item: @item)

    assert_equal :taken, Agents::Claim.call(agent: @baby, item: stale).error
    assert_equal @cursor, @item.reload.claimed_by_agent
  end

  test "two concurrent claims on one item leave exactly one winner" do
    gate = Concurrent::CyclicBarrier.new(2)
    results = [ @cursor, @baby ].map do |agent|
      Thread.new do
        item = Item.find(@item.id)
        gate.wait
        Agents::Claim.call(agent: agent, item: item)
      end
    end.map(&:value)

    assert_equal 1, results.count(&:success?)
    assert_equal [ :taken ], results.reject(&:success?).map(&:error)
    assert_equal 1, @item.events.where(kind: "claimed").count
    assert_equal results.find(&:success?).item.claimed_by_agent, @item.reload.claimed_by_agent
  end

  test "claiming an item the agent already holds succeeds without a second event" do
    Agents::Claim.call(agent: @cursor, item: @item)

    assert_no_difference -> { ItemEvent.count } do
      assert Agents::Claim.call(agent: @cursor, item: @item).success?
    end
  end

  test "a handled or dismissed item cannot be claimed" do
    result = Agents::Claim.call(agent: @cursor, item: items(:handled_email))

    assert_equal :not_claimable, result.error
    assert items(:handled_email).reload.status_handled?
  end

  test "a revoked agent cannot claim" do
    assert_equal :revoked, Agents::Claim.call(agent: agents(:revoked), item: @item).error
    assert_nil @item.reload.claimed_by_agent
  end
end
