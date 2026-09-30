require "test_helper"

class ResolveAnomalyToolTest < ActionDispatch::IntegrationTest
  include McpHelper
  include AnomalyHelper

  setup do
    host! "localhost"
    WebmcpToolsController::RATE_LIMIT_STORE.clear
    @anomaly = create_anomaly!
    @incident = Incident.for_anomaly!(@anomaly)
  end

  def webmcp_tool(name, arguments)
    post webmcp_tool_path(name), params: { arguments: }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :success
    response.parsed_body["result"]
  end

  test "over MCP it resolves the anomaly's incident as the calling agent, with the note" do
    payload = tool_payload(mcp_tool("resolve_anomaly", { anomaly_id: @anomaly.id, note: "Rolled back the sync change" }))

    assert_equal "resolved", payload.dig("incident", "status")
    assert_equal "Rolled back the sync change", payload.dig("incident", "resolution_note")
    @incident.reload
    assert_equal agents(:cursor), @incident.resolved_by
    assert_equal "Cursor", @incident.resolved_by_name
    assert_predicate @anomaly.reload, :resolved?
    assert items(:angry_slack).reload.status_new?, "items are left alone unless handle_items is set"
  end

  test "over WebMCP it resolves as the signed-in person's browser agent, and both surfaces agree afterwards" do
    sign_in_as users(:every_ana)

    payload = tool_payload(webmcp_tool("resolve_anomaly", { anomaly_id: @anomaly.id, handle_items: true }))

    assert_equal Agent.browser_for(users(:every_ana)), @incident.reload.resolved_by
    assert payload.dig("incident", "items_handled")
    assert items(:angry_slack).reload.status_handled?
    again = webmcp_tool("resolve_anomaly", { anomaly_id: @anomaly.id })
    assert_equal mcp_tool("resolve_anomaly", { anomaly_id: @anomaly.id }), again
    assert_equal "Incident #{@incident.id} is already resolved.", tool_error_text(again)
  end

  test "bad news from before incidents existed gets an incident to resolve" do
    older = create_anomaly!(status: "ended", ended_at: 1.day.ago)

    tool_payload(mcp_tool("resolve_anomaly", { anomaly_id: older.id }))

    assert_predicate older.reload.incident, :resolved?
  end

  test "good news and unknown anomalies are tool errors" do
    positive = create_anomaly!(polarity: "positive", severity: nil, highlight: "big", metric: "mood_share", dimension: "beaming")

    assert_equal "Anomaly #{positive.id} is not bad news, so it has no incident to resolve.",
      tool_error_text(mcp_tool("resolve_anomaly", { anomaly_id: positive.id }))
    assert_equal "Anomaly 0 was not found.", tool_error_text(mcp_tool("resolve_anomaly", { anomaly_id: 0 }))
  end
end
