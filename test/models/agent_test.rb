require "test_helper"

class AgentTest < ActiveSupport::TestCase
  test "stores only a token digest" do
    assert_equal Agent.digest("cursor-test-token"), agents(:cursor).token_digest
    refute_equal "cursor-test-token", agents(:cursor).token_digest
  end

  test "active excludes revoked agents" do
    assert agents(:revoked).revoked?
    assert_not_includes Agent.active, agents(:revoked)
    assert_includes Agent.active, agents(:cursor)
  end

  test "name and digest are unique" do
    agent = Agent.new(name: "Cursor", token_digest: agents(:cursor).token_digest)

    refute agent.valid?
    assert agent.errors.key?(:name)
    assert agent.errors.key?(:token_digest)
  end
end
