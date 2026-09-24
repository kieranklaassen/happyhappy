require "test_helper"

# F2 end to end: an agent works the feed over /mcp with its bearer token, the
# team sees each step on the item's timeline, and a subscribed outbound
# endpoint receives a signed agent.reported delivery (stubbed).
class AgentFlowTest < ActionDispatch::IntegrationTest
  include McpHelper
  include WebhookEndpointHelper

  setup do
    host! "localhost"
    @item = items(:angry_slack)
    @endpoint = create_webhook_endpoint(events: %w[agent.reported], product_ids: [ products(:cora).id ])
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 200)
  end

  test "covers F2: an agent lists, claims, and reports on an item over /mcp and the timeline shows each step" do
    perform_enqueued_jobs(only: WebhookDeliveryJob) do
      listed = tool_payload(mcp_tool("list_items", { product: "cora", sentiment: "complaint", status: "new" }))
      assert_includes listed["items"].map { |item| item["id"] }, @item.id

      claimed = tool_payload(mcp_tool("claim_item", { item_id: @item.id }))["item"]
      assert_equal "claimed", claimed["status"]
      assert_equal "Cursor", claimed["claimed_by"]

      progress = tool_payload(mcp_tool("report_item", {
        item_id: @item.id, summary: "Looking into the archive rule.", status: "in_progress"
      }))["item"]
      assert_equal "in_progress", progress["status"]

      done = tool_payload(mcp_tool("report_item", {
        item_id: @item.id, summary: "Restored the inbox and replied.", status: "handled",
        link: "https://example.com/reply/1"
      }))["item"]
      assert_equal "handled", done["status"]
      assert_nil done["claimed_by"]
    end

    timeline = tool_payload(mcp_tool("get_item", { item_id: @item.id }))["item"]["timeline"]
    steps = timeline.map { |event| [ event["kind"], event.dig("actor", "name") ] }
    assert_equal [ [ "claimed", "Cursor" ], [ "reported", "Cursor" ], [ "reported", "Cursor" ] ], steps.last(3)
    assert_equal "Restored the inbox and replied.", timeline.last.dig("data", "summary")

    sign_in_as users(:every_ana)
    get item_path(@item)
    assert_equal "handled", inertia.props[:item][:status]
    assert_equal %w[claimed reported reported], inertia.props[:events].map { |event| event[:kind] }.last(3)

    deliveries = @endpoint.deliveries.order(:id)
    assert_equal %w[agent.reported agent.reported], deliveries.map(&:event)
    assert deliveries.all?(&:succeeded?)
    assert_requested(:post, WEBHOOK_TEST_URL, times: 1) do |request|
      body = JSON.parse(request.body)
      Webhooks::Signature.verify(@endpoint.secret, request.body, request.headers["X-Happyhappy-Signature"]) &&
        body["event"] == "agent.reported" && body.dig("item", "id") == @item.id &&
        body.dig("data", "summary") == "Restored the inbox and replied."
    end
  end

  test "covers AE7: once agent A has claimed an item, agent B's claim is refused and B is told it is taken" do
    tool_payload(mcp_tool("claim_item", { item_id: @item.id }, token: "cursor-test-token"))

    text = tool_error_text(mcp_tool("claim_item", { item_id: @item.id }, token: "baby-agent-test-token"))

    assert_equal "Item #{@item.id} is already claimed by Cursor.", text
    assert_equal agents(:cursor), @item.reload.claimed_by_agent
    listed = tool_payload(mcp_tool("list_items", { status: "claimed" }, token: "baby-agent-test-token"))
    assert_equal "Cursor", listed["items"].find { |item| item["id"] == @item.id }["claimed_by"]
  end
end
