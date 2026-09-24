require "test_helper"

class Agents::AuthenticateTest < ActiveSupport::TestCase
  test "a valid token resolves to its agent" do
    result = Agents::Authenticate.call(token: "cursor-test-token")

    assert result.success?
    assert_equal agents(:cursor), result.agent
  end

  test "surrounding whitespace is ignored" do
    assert_equal agents(:cursor), Agents::Authenticate.call(token: "  cursor-test-token\n").agent
  end

  test "a revoked token fails authentication" do
    result = Agents::Authenticate.call(token: "revoked-test-token")

    assert result.failure?
    assert_equal :revoked, result.error
    assert_nil result.agent
  end

  test "an unknown token fails authentication" do
    assert_equal :invalid_token, Agents::Authenticate.call(token: "nope").error
  end

  test "a missing token fails authentication" do
    assert_equal :missing_token, Agents::Authenticate.call(token: nil).error
    assert_equal :missing_token, Agents::Authenticate.call(token: " ").error
  end

  test "an issued token authenticates and only its digest is stored" do
    agent, token = Agent.issue(name: "Codex")
    agent.save!

    assert_not_includes agent.attributes.values.map(&:to_s), token
    assert_equal agent, Agents::Authenticate.call(token: token).agent
  end
end
