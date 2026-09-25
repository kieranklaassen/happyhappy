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

  test "browser_for creates one browser agent per person and reuses it" do
    user = users(:every_ana)

    agent = assert_difference -> { Agent.count } => 1 do
      Agent.browser_for(user)
    end
    assert_equal "Ana Every (WebMCP)", agent.name
    assert_equal user, agent.user
    assert_no_difference -> { Agent.count } do
      assert_equal agent, Agent.browser_for(user.reload)
    end
  end

  test "browser_for falls back to the email address when the name is taken" do
    Agent.create!(name: "Ana Every (WebMCP)", token_digest: Agent.digest("squatter"))

    assert_equal "ana@every.to (WebMCP)", Agent.browser_for(users(:every_ana)).name
  end

  test "a browser agent credits its person; other agents credit themselves" do
    browser = Agent.browser_for(users(:every_ana))

    assert_equal users(:every_ana), browser.event_actor
    assert_equal agents(:cursor), agents(:cursor).event_actor
  end

  test "name and digest are unique" do
    agent = Agent.new(name: "Cursor", token_digest: agents(:cursor).token_digest)

    refute agent.valid?
    assert agent.errors.key?(:name)
    assert agent.errors.key?(:token_digest)
  end
end
