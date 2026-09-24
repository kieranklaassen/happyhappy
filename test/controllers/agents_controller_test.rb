require "test_helper"

class AgentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the agents page lists agents without any token material" do
    get agents_path

    assert_response :success
    assert_inertia_component "agents/index"
    names = inertia.props[:agents].map { |agent| agent[:name] }
    assert_equal [ "Baby Agent", "Cursor", "Retired bot" ], names
    cursor = inertia.props[:agents].find { |agent| agent[:name] == "Cursor" }
    assert_equal 1, cursor[:claimed_count]
    assert_nil inertia.props[:new_token]
    assert_not_includes response.body, agents(:cursor).token_digest
  end

  test "the agents screen shows the token once after creation" do
    assert_difference -> { Agent.count } => 1 do
      post agents_path, params: { agent: { name: "Codex" } }
    end

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    token = inertia.props[:new_token][:token]
    agent = Agent.find_by!(name: "Codex")
    assert_equal agent.id, inertia.props[:new_token][:agent_id]
    assert_equal Agent.digest(token), agent.token_digest
    assert_equal agent, Agents::Authenticate.call(token: token).agent
    assert_nil flash[:agent_token]

    get agents_path

    assert_nil inertia.props[:new_token]
    assert_not_includes response.body, token
  end

  test "a duplicate name is refused with an error" do
    assert_no_difference -> { Agent.count } do
      post agents_path, params: { agent: { name: "Cursor" } }
    end

    assert_redirected_to agents_path
    follow_redirect!
    assert_match "taken", inertia.props[:errors][:name]
  end

  test "revoking an agent cuts it off immediately" do
    patch revoke_agent_path(agents(:cursor))

    assert_redirected_to agents_path
    assert agents(:cursor).reload.revoked?
    assert_equal :revoked, Agents::Authenticate.call(token: "cursor-test-token").error
  end

  test "the agents page requires sign-in" do
    sign_out

    get agents_path

    assert_redirected_to new_session_path
  end
end
