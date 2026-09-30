require "test_helper"

class Slack::IncidentMessageTest < ActiveSupport::TestCase
  include AnomalyHelper

  setup do
    products(:cora).update!(alert_channel_id: "C0AGCDCD6KG", alert_mention_ids: %w[U0AGQDHRV8U])
    @anomaly = create_anomaly!(source: nil, expected: 6, actual: 42, metric: "volume", dimension: nil)
    @incident = Incident.for_anomaly!(@anomaly)
  end

  def render(interactive: false)
    Slack::IncidentMessage.new(@incident.reload, interactive: interactive).to_h
  end

  def actions(payload)
    payload[:blocks].find { |block| block[:type] == "actions" }
  end

  test "says what spiked with expected against actual, the sources, the customers behind it, and a link to the incident" do
    create_anomaly!(source: sources(:intercom_inbox), incident: @incident)

    payload = render
    rendered = JSON.generate(payload[:blocks])

    assert_equal "Cora incident: message volume spiked <@U0AGQDHRV8U>", payload[:text]
    assert_includes rendered, "Message volume across all sources: 42, usually 6 (high)"
    assert_includes rendered, "Bug messages on Intercom"
    assert_includes rendered, "*Sources*"
    assert_includes rendered, "/items/#{items(:angry_slack).id}"
    assert_equal "http://localhost:3000/incidents/#{@incident.id}", actions(payload)[:elements].first[:url]
  end

  test "customer text is escaped and can never mention the channel" do
    items(:angry_slack).messages.from_customers.last.update!(body: "<!channel> @here see <https://evil.example|your invoice> & more")

    rendered = JSON.generate(render[:blocks])

    assert_not_includes rendered, "<!channel>"
    assert_not_includes rendered, "<https://evil.example"
    assert_includes rendered, "&lt;!channel&gt;"
    assert_includes rendered, "@\u200Bhere"
    assert_includes rendered, "&amp; more"
  end

  test "Mark resolved is an action button with interactivity on" do
    button = actions(render(interactive: true))[:elements].last

    assert_equal "incident_resolve", button[:action_id]
    assert_equal @incident.id.to_s, button[:value]
    assert_nil button[:url]
  end

  test "Mark resolved links to the incident page when interactivity is off, never both url and action" do
    button = actions(render(interactive: false))[:elements].last

    assert_equal "http://localhost:3000/incidents/#{@incident.id}#resolve", button[:url]
    assert_nil button[:action_id]
  end

  test "interactivity defaults to the Settings switch" do
    Setting.current.update!(slack_interactivity: true)

    assert_equal "incident_resolve", actions(Slack::IncidentMessage.new(@incident).to_h)[:elements].last[:action_id]
  end

  test "a resolved incident says who resolved it, without buttons or mentions" do
    @incident.update!(status: :resolved, resolved_at: Time.current, resolved_by_name: "Ana <b>", resolution_note: "IMAP sync fixed")

    payload = render
    rendered = JSON.generate(payload[:blocks])

    assert_nil actions(payload)
    assert_not_includes rendered, "<@U0AGQDHRV8U>"
    assert_includes rendered, "Resolved* by Ana &lt;b&gt;: IMAP sync fixed"
    assert payload[:text].start_with?("Resolved: Cora incident")
  end
end
