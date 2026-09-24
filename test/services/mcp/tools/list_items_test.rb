require "test_helper"

class Mcp::Tools::ListItemsTest < ActiveSupport::TestCase
  def call(**arguments)
    Mcp::Tools::ListItems.call(server_context: { agent: agents(:cursor) }, **arguments)
  end

  test "defaults to relevant items, most recent first" do
    payload = call.structured_content

    assert_equal ItemsQuery.new.call.ids, payload["items"].map { |item| item["id"] }
    assert_not_includes payload["items"].map { |item| item["id"] }, items(:not_relevant_slack).id
    assert_nil payload["next_offset"]
  end

  test "pages with limit and next_offset" do
    first = call(limit: 2).structured_content
    second = call(limit: 2, offset: first["next_offset"]).structured_content

    assert_equal 2, first["items"].size
    assert_equal 2, first["next_offset"]
    assert_equal ItemsQuery.new.call.ids.drop(2).first(2), second["items"].map { |item| item["id"] }
  end

  test "status and needs_review filters narrow the list" do
    assert_equal [ items(:claimed_intercom).id ], call(status: [ "claimed" ]).structured_content["items"].map { |item| item["id"] }
    assert_equal [ items(:needs_review_x).id ], call(needs_review: true).structured_content["items"].map { |item| item["id"] }
  end

  test "an invalid time is a tool error" do
    response = call(since: "yesterday-ish")

    assert response.error?
    assert_equal "Invalid filter since: must be an ISO 8601 time", response.content.first[:text]
  end
end
