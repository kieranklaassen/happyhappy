# frozen_string_literal: true

require "test_helper"

class WebmcpTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "signed-in pages share the ToolRegistry manifest as the webmcp prop" do
    sign_in_as(users(:every_ana))
    get agents_path

    assert_equal ToolRegistry.manifest.deep_stringify_keys, inertia.props[:webmcp].deep_stringify_keys
  end

  test "signed-out pages share webmcp: nil, so the page registers no tools" do
    get new_session_path

    assert inertia.props.key?(:webmcp)
    assert_nil inertia.props[:webmcp]
  end

  test "signing out turns the prop back to nil on the next visit" do
    sign_in_as(users(:every_ana))
    delete session_path
    get new_session_path

    assert_nil inertia.props[:webmcp]
  end

  test "partial reloads that do not ask for webmcp skip it" do
    sign_in_as(users(:every_ana))

    get agents_path, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => ViteRuby.digest.to_s,
      "X-Inertia-Partial-Component" => "agents/index",
      "X-Inertia-Partial-Data" => "agents"
    }

    assert_response :success
    assert inertia.props.key?(:agents)
    assert_not inertia.props.key?(:webmcp)
  end

  test "origin-trial tokens: one per whitespace- or comma-separated value, malformed ones dropped" do
    env = { Webmcp::ORIGIN_TRIAL_ENV => "AbC+/12= , Zz9==\nbad\"><script>" }
    assert_equal [ "AbC+/12=", "Zz9==" ], Webmcp.origin_trial_tokens(env)
    assert_empty Webmcp.origin_trial_tokens({})
  end

  test "the layout emits an origin-trial meta tag per token and none when unset" do
    get new_session_path
    assert_select "meta[http-equiv=origin-trial]", count: 0

    ENV[Webmcp::ORIGIN_TRIAL_ENV] = "TokenA== TokenB=="
    get new_session_path
    assert_select "meta[http-equiv=origin-trial][content=?]", "TokenA=="
    assert_select "meta[http-equiv=origin-trial][content=?]", "TokenB=="
  ensure
    ENV.delete(Webmcp::ORIGIN_TRIAL_ENV)
  end
end
