require "test_helper"

class ItemSearchesControllerTest < ActionDispatch::IntegrationTest
  include TrufflerHelper
  include ActiveJob::TestHelper

  setup do
    @user = users(:every_ana)
    sign_in_as @user
    index_items_for_search!
  end

  def angry_cora_fake
    Truffler.config.client.answer("intent__anger", "filter").answer("intent__product", "filter").answer("option__product", "cora")
  end

  def partial_reload(params, only:)
    get items_path, params: params, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => ViteRuby.digest.to_s,
      "X-Inertia-Partial-Component" => "items/index",
      "X-Inertia-Partial-Data" => only
    }
    assert_response :success
  end

  test "requires sign in" do
    sign_out
    post item_search_path, params: { q: "cora" }

    assert_redirected_to new_session_path
  end

  test "a query on the feed returns ranked items and the search chips, with no Smart run yet" do
    get items_path, params: { q: "cora last 3 hours", status: [ "new" ] }

    assert_inertia_component "items/index"
    assert_equal [ items(:angry_slack).id ], inertia.props[:items].pluck(:id)
    search = inertia.props[:search]
    assert_equal "cora last 3 hours", search[:query]
    assert_equal [ "time" ], search[:chips].pluck(:key)
    assert_equal "pending", search[:encoding_status].to_s
    assert_equal "enter", search[:explicit_action].to_s
    assert_nil inertia.props[:smart]
    assert_equal [ "new" ], inertia.props[:filters][:status]
  end

  test "a removed chip is dropped" do
    get items_path, params: { q: "cora last 3 hours", removed: [ "time" ] }

    assert_equal [ "time" ], inertia.props[:search][:removed]
    assert_empty inertia.props[:search][:chips]
    assert_includes inertia.props[:items].pluck(:id), items(:handled_email).id
  end

  test "Enter starts a Smart run and redirects to the feed with its run id; the run streams in buckets" do
    angry_cora_fake.answer(:relevance, 0.9)
    encode_query!("angry cora", user: @user)

    perform_enqueued_jobs { post item_search_path, params: { q: "angry cora", status: [ "new" ] } }
    run_id = Rack::Utils.parse_nested_query(URI(response.location).query).fetch("run_id")
    assert_redirected_to items_path(q: "angry cora", status: [ "new" ], run_id: run_id)

    partial_reload({ q: "angry cora", status: [ "new" ], run_id: run_id }, only: "smart")
    smart = inertia.props[:smart]

    assert_not inertia.props.key?(:items)
    assert_equal run_id, smart[:run_id]
    assert_equal [ items(:angry_slack).id ], smart[:buckets][:strong].pluck(:id)
    assert_in_delta 0.9, smart[:buckets][:strong].first[:score]
    assert_equal [ "unlikely" ], smart[:collapsed].map(&:to_s)
  end

  test "a bucket never shows an item the feed filters drop" do
    angry_cora_fake.answer(:relevance, 0.9)
    encode_query!("angry cora", user: @user)
    perform_enqueued_jobs { post item_search_path, params: { q: "angry cora" } }
    run_id = Rack::Utils.parse_nested_query(URI(response.location).query).fetch("run_id")

    items(:angry_slack).update_columns(status: "dismissed")
    partial_reload({ q: "angry cora", status: [ "new" ], run_id: run_id }, only: "smart")

    assert_empty inertia.props[:smart][:buckets][:strong]
  end

  test "a new query without the run id cancels the searcher's run" do
    angry_cora_fake
    encode_query!("angry cora", user: @user)
    post item_search_path, params: { q: "angry cora" }
    run_id = Rack::Utils.parse_nested_query(URI(response.location).query).fetch("run_id")

    get items_path, params: { q: "angry cora billing" }

    assert_equal :cancelled, FeedSearch.find_run(run_id, user: @user).status
  end

  test "an invalid filter is a feed error, and Enter with one keeps only the query" do
    get items_path, params: { q: "cora", status: [ "lost" ] }
    assert_match "not valid", inertia.props[:error]

    post item_search_path, params: { q: "cora", status: [ "lost" ] }
    assert_redirected_to items_path(q: "cora")
  end
end
