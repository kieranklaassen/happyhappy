require "test_helper"

class Agents::ResultTest < ActiveSupport::TestCase
  test "success wraps an item and exposes it only through value and item" do
    item = items(:angry_slack)
    result = Agents::Result.success(item)

    assert result.success?
    assert_not result.failure?
    assert_equal item, result.value
    assert_equal item, result.item
    assert_nil result.agent
    assert_nil result.error
    assert_nil result.message
  end

  test "success wraps an agent and exposes it only through value and agent" do
    agent = agents(:cursor)
    result = Agents::Result.success(agent)

    assert result.success?
    assert_not result.failure?
    assert_equal agent, result.value
    assert_equal agent, result.agent
    assert_nil result.item
    assert_nil result.error
    assert_nil result.message
  end

  test "success with another value returns nil for both item and agent" do
    result = Agents::Result.success("ok")

    assert result.success?
    assert_not result.failure?
    assert_equal "ok", result.value
    assert_nil result.item
    assert_nil result.agent
  end

  test "failure accepts every documented agent error code" do
    Agents::Result::ERRORS.each do |code|
      result = Agents::Result.failure(code, "failed because #{code}")

      assert_not result.success?, "expected #{code.inspect} to be a failure"
      assert result.failure?
      assert_nil result.value
      assert_nil result.item
      assert_nil result.agent
      assert_equal code, result.error
      assert_equal "failed because #{code}", result.message
    end
  end

  test "failure rejects unknown or non-symbol error codes" do
    [ :unknown, "taken", nil ].each do |bad_error|
      error = assert_raises(ArgumentError) do
        Agents::Result.failure(bad_error, "nope")
      end

      assert_match(/unknown agent error/, error.message)
    end
  end

  test "behaves as an immutable value object" do
    first = Agents::Result.failure(:taken, "already claimed")
    second = Agents::Result.failure(:taken, "already claimed")
    different = Agents::Result.failure(:revoked, "already claimed")

    assert_equal first, second
    assert_not_equal first, different
    assert first.frozen?
  end
end
