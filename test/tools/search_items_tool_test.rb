require "test_helper"

class SearchItemsToolTest < ActiveSupport::TestCase
  include TrufflerHelper
  include ActiveJob::TestHelper

  setup { index_items_for_search! }

  def call(**arguments)
    SearchItemsTool.call(server_context: { agent: agents(:cursor) }, **arguments)
  end

  test "waits for the query encoding, then returns chips and ranked items with customer text marked untrusted" do
    Truffler.config.client.answer("intent__anger", "filter").answer("intent__product", "filter").answer("option__product", "cora")

    payload = perform_enqueued_jobs(only: Truffler::Jobs::EncodeQueryJob) { call(query: "angry cora") }.structured_content

    assert_equal "cached", payload["encoding"].to_s
    assert_equal [ "anger", "product:cora" ], payload["chips"].pluck("key").sort
    assert_equal [ items(:angry_slack).id ], payload["items"].pluck("id")
    assert_equal true, payload["items"].first.dig("excerpt", "untrusted")
  end

  test "a filter nothing matched is reported as relaxed" do
    Truffler.config.client.answer("intent__product", "filter").answer("option__product", "cora")
      .answer("intent__source", "filter").answer("option__source", "custom")

    payload = perform_enqueued_jobs(only: Truffler::Jobs::EncodeQueryJob) { call(query: "cora custom") }.structured_content

    assert_equal [ "source:custom" ], payload["relaxed_labels"]
    assert_equal "Nothing matched Source: custom; showing results without it.", payload["relaxed_notice"]
    assert_equal true, payload["chips"].find { |chip| chip["key"] == "source:custom" }["relaxed"]
    assert_includes payload["items"].pluck("id"), items(:angry_slack).id
  end

  test "takes list_items filters, a time phrase, and removed chips" do
    payload = perform_enqueued_jobs(only: Truffler::Jobs::EncodeQueryJob) do
      call(query: "cora last 3 hours", status: [ "new", "claimed" ], removed_chips: [ "time" ])
    end.structured_content

    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ].sort, payload["items"].pluck("id").sort
    assert_empty payload["chips"]
  end

  test "sort and invalid filters are tool errors" do
    assert_equal "Invalid filter sort: search results are ranked by relevance", call(query: "cora", sort: "newest").content.first[:text]
    assert_match "status", call(query: "cora", status: [ "lost" ]).content.first[:text]
  end
end
