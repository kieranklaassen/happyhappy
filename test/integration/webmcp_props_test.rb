require "test_helper"

# The WebMCP manifest rides as a lazy shared Inertia prop: present on every signed-in page, absent when
# signed out and from partial reloads that do not ask for it.
class WebmcpPropsTest < ActionDispatch::IntegrationTest
  TOOLS = %w[list_items get_item claim_item release_item report_item list_anomalies].freeze

  setup { host! "localhost" }

  test "signed-in pages ship the registry's tools as request tools on this origin" do
    sign_in_as users(:every_ana)

    get agents_path, headers: browser

    assert_response :success
    manifest = inertia.props[:webmcp]
    assert_equal TOOLS, manifest[:tools].pluck(:name)
    list_items = manifest[:tools].first
    assert_equal "request", list_items[:kind]
    assert_equal "http://localhost/webmcp/tools/list_items", list_items[:request][:url]
    assert_equal "omit", list_items[:request][:agent_identity]
  end

  test "signed-out pages ship no manifest" do
    get new_session_path, headers: browser

    assert_response :success
    assert_nil inertia.props[:webmcp]
  end

  test "partial reloads that do not ask for webmcp skip it" do
    sign_in_as users(:every_ana)

    get agents_path, headers: browser.merge(
      "X-Inertia" => "true",
      "X-Inertia-Version" => ViteRuby.digest.to_s,
      "X-Inertia-Partial-Component" => "agents/index",
      "X-Inertia-Partial-Data" => "agents"
    )

    assert_response :success
    assert inertia.props.key?(:agents)
    assert_not inertia.props.key?(:webmcp)
  end

  private

  def browser
    { "User-Agent" => "Mozilla/5.0" }
  end
end
