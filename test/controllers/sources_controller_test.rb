# frozen_string_literal: true

require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:every_ana) }

  test "index shows every source with its health" do
    get sources_path

    assert_response :success
    assert_inertia_component "sources/index"
    sources = inertia.props[:sources].index_by { |source| source[:id] }
    assert_equal Source.count, sources.size

    slack = sources.fetch(sources(:slack_community).id)
    assert_equal "slack", slack[:kind]
    assert_equal "active", slack[:status]
    assert_equal "Cora", slack[:default_product_name]
    assert_equal sources(:slack_community).last_message_at.iso8601, slack[:last_message_at]
    assert_nil slack[:last_error]

    lex = sources.fetch(sources(:lex_legacy).id)
    assert_equal "Slack: channel_not_found", lex[:last_error]
    assert_equal "Lex", lex[:default_product_name]

    assert_nil sources.fetch(sources(:intercom_inbox).id)[:default_product_name]
  end

  test "index shows X spend against the monthly limit and the budget pause" do
    get sources_path

    sources = inertia.props[:sources].index_by { |source| source[:id] }
    mentions = sources.fetch(sources(:x_mentions).id)
    assert_equal 50.0, mentions[:monthly_limit]
    assert_equal 12.5, mentions[:month_spend]

    paused = sources.fetch(sources(:x_budget_paused).id)
    assert_equal "paused_for_budget", paused[:status]
    assert_equal 10.0, paused[:month_spend]
  end

  test "spend from an earlier month shows as zero" do
    sources(:x_mentions).update!(month_key: "2020-01")

    get sources_path

    assert_equal 0.0, inertia.props[:sources].find { |source| source[:id] == sources(:x_mentions).id }[:month_spend]
  end

  test "new offers every kind and only active products" do
    get new_source_path

    assert_inertia_component "sources/form"
    assert_equal %w[slack discord intercom email x custom], inertia.props[:kinds]
    assert_equal %w[Cora Sparkle Spiral], inertia.props[:products].map { |product| product[:name] }
    assert_nil inertia.props[:source][:id]
  end

  test "an X source saves its query and monthly limit" do
    post sources_path, params: { source: {
      kind: "x", name: "X search for Sparkle", selector: "sparkle app -is:retweet",
      monthly_limit: "25", default_product_id: products(:sparkle).id
    } }

    assert_redirected_to sources_path
    source = Source.find_by!(name: "X search for Sparkle")
    assert source.x?
    assert_equal "sparkle app -is:retweet", source.selector
    assert_equal 25, source.monthly_limit
    assert_equal products(:sparkle), source.default_product
    assert source.active?

    follow_redirect!
    row = inertia.props[:sources].find { |item| item[:id] == source.id }
    assert_equal 25.0, row[:monthly_limit]
    assert_equal 0.0, row[:month_spend]
  end

  test "a source with no default product is allowed" do
    post sources_path, params: { source: { kind: "discord", name: "Community Discord", selector: "1100000000000000099",
      default_product_id: "" } }

    assert_redirected_to sources_path
    assert_nil Source.find_by!(name: "Community Discord").default_product
  end

  test "a monthly limit is ignored for kinds other than X" do
    post sources_path, params: { source: { kind: "slack", name: "Slack #spiral", selector: "C0SPIRAL", monthly_limit: "5" } }

    assert_nil Source.find_by!(name: "Slack #spiral").monthly_limit
  end

  test "a duplicate selector for the same kind shows a validation error" do
    assert_no_difference -> { Source.count } do
      post sources_path, params: { source: { kind: "slack", name: "Dupe", selector: "C0COMMUNITY" } }
    end

    assert_redirected_to new_source_path
    follow_redirect!
    assert_equal [ "has already been taken" ], inertia.props[:errors]["selector"]
  end

  test "an unknown kind shows a validation error" do
    post sources_path, params: { source: { kind: "reddit", name: "Reddit", selector: "r/every" } }

    follow_redirect!
    assert inertia.props[:errors]["kind"].present?
  end

  test "edit keeps a retired default product selectable" do
    get edit_source_path(sources(:lex_legacy))

    assert_inertia_component "sources/form"
    assert_equal products(:lex).id, inertia.props[:source][:default_product_id]
    assert_includes inertia.props[:products].map { |product| product[:name] }, "Lex"
  end

  test "update changes the name, selector, and default product but never the kind" do
    patch source_path(sources(:intercom_inbox)), params: { source: {
      kind: "x", name: "Intercom Cora team", selector: "7000002", default_product_id: products(:cora).id
    } }

    assert_redirected_to sources_path
    source = sources(:intercom_inbox).reload
    assert source.intercom?
    assert_equal "Intercom Cora team", source.name
    assert_equal "7000002", source.selector
    assert_equal products(:cora), source.default_product
  end

  test "raising an X monthly limit above this month's spend resumes a budget-paused source" do
    patch source_path(sources(:x_budget_paused)), params: { source: { monthly_limit: "20" } }

    source = sources(:x_budget_paused).reload
    assert_equal 20, source.monthly_limit
    assert source.active?
  end

  test "a limit still at or below this month's spend keeps the source paused for budget" do
    patch source_path(sources(:x_budget_paused)), params: { source: { monthly_limit: "10" } }
    assert sources(:x_budget_paused).reload.paused_for_budget?

    patch source_path(sources(:x_budget_paused)), params: { source: { name: "X search for Spiral app" } }
    assert sources(:x_budget_paused).reload.paused_for_budget?
  end

  test "a negative monthly limit is rejected" do
    patch source_path(sources(:x_mentions)), params: { source: { monthly_limit: "-1" } }

    assert_redirected_to edit_source_path(sources(:x_mentions))
    follow_redirect!
    assert inertia.props[:errors]["monthly_limit"].present?
  end

  test "a custom webhook source gets its URL and secret and opens on its edit page" do
    post sources_path, params: { source: { kind: "custom", name: "Spiral app feedback", selector: "",
      default_product_id: products(:spiral).id } }

    source = Source.find_by!(name: "Spiral app feedback")
    assert source.custom?
    assert_redirected_to edit_source_path(source)
    follow_redirect!
    assert_equal "http://www.example.com/webhooks/custom/#{source.public_token}", inertia.props[:webhook][:url]
    assert_equal source.signing_secret, inertia.props[:webhook][:signing_secret]
  end

  test "a custom webhook source needs a product" do
    assert_no_difference -> { Source.count } do
      post sources_path, params: { source: { kind: "custom", name: "Orphan", selector: "" } }
    end

    follow_redirect!
    assert inertia.props[:errors]["default_product_id"].present?
  end

  test "index shows the webhook URL for custom sources only" do
    get sources_path

    rows = inertia.props[:sources].index_by { |source| source[:id] }
    assert_equal "http://www.example.com/webhooks/custom/cora-app-webhook-token",
      rows.fetch(sources(:cora_app_webhook).id)[:webhook_url]
    assert_nil rows.fetch(sources(:slack_community).id)[:webhook_url]
    assert_not(rows.values.any? { |row| row.key?(:signing_secret) })
  end

  test "edit shows no webhook for other kinds" do
    get edit_source_path(sources(:slack_community))

    assert_nil inertia.props[:webhook]
  end

  test "rotating a custom source's secret replaces it" do
    patch rotate_secret_source_path(sources(:cora_app_webhook))

    assert_redirected_to edit_source_path(sources(:cora_app_webhook))
    assert_not_equal "hhsec_cora-app-test-secret", sources(:cora_app_webhook).reload.signing_secret
  end

  test "rotating is only for custom sources" do
    patch rotate_secret_source_path(sources(:slack_community))

    assert_response :not_found
  end
end
