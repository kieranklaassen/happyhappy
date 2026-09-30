require "test_helper"

class Incidents::ResolveTest < ActiveJob::TestCase
  include AnomalyHelper
  include SlackStubHelper
  include WebhookEndpointHelper

  setup do
    @user = users(:every_ana)
    @anomaly = create_anomaly!(item_ids: [ items(:angry_slack).id, items(:claimed_intercom).id, items(:handled_email).id ])
    @per_source = create_anomaly!(source: sources(:slack_community))
    @incident = Incident.for_anomaly!(@anomaly)
    @per_source.update!(incident: @incident)
    @incident.update!(slack_channel_id: "C0AGCDCD6KG", slack_message_ts: SLACK_OK_TS)
    stub_slack_method("chat.update")
    stub_slack_method("chat.postMessage", { ok: true, ts: "1727200001.000100" })
  end

  def resolve(**options)
    perform_enqueued_jobs(only: PostIncidentResolutionJob) do
      Incidents::Resolve.call(incident: @incident, actor: @user, note: "Fixed the IMAP sync", **options)
    end
  end

  test "ends every anomaly of the incident with who, when, and the note" do
    freeze_time do
      assert_predicate resolve, :success?

      @incident.reload
      assert_predicate @incident, :resolved?
      assert_equal Time.current, @incident.resolved_at
      assert_equal @user, @incident.resolved_by
      assert_equal "Ana Every", @incident.resolved_by_name
      assert_equal "Fixed the IMAP sync", @incident.resolution_note
      [ @anomaly, @per_source ].each do |anomaly|
        anomaly.reload
        assert_predicate anomaly, :ended?
        assert_equal Time.current, anomaly.resolved_at
      end
    end
  end

  test "threads Resolved by under the original ping and marks the ping resolved" do
    resolve

    reply = slack_calls_to("chat.postMessage").sole
    assert_equal [ "C0AGCDCD6KG", SLACK_OK_TS ], reply.values_at("channel", "thread_ts")
    assert_equal ":white_check_mark: Resolved by Ana Every: Fixed the IMAP sync", reply["text"]
    update = slack_calls_to("chat.update").sole
    assert_equal SLACK_OK_TS, update["ts"]
    assert_includes update["blocks"].to_json, "Resolved* by Ana Every"
    assert_not_includes update["blocks"].to_json, "Mark resolved"
  end

  test "an incident that never pinged posts nothing to Slack" do
    @incident.update!(slack_channel_id: nil, slack_message_ts: nil)

    resolve

    assert_empty slack_calls
  end

  test "leaves the driving items alone by default" do
    assert_no_difference -> { ItemEvent.count } do
      resolve
    end
    assert items(:angry_slack).reload.status_new?
  end

  test "with handle_items marks driving items that still need attention handled, with the note as the reason" do
    resolve(handle_items: true)

    angry = items(:angry_slack).reload
    assert angry.status_handled?
    event = angry.events.status_changed.last
    assert_equal @user, event.actor
    assert_equal "Incident resolved by Ana Every: Fixed the IMAP sync", event.data["reason"]
    claimed = items(:claimed_intercom).reload
    assert claimed.status_handled?
    assert_nil claimed.claimed_by_agent
    assert_equal 0, items(:handled_email).events.status_changed.where(created_at: 1.minute.ago..).count
    assert @incident.reload.items_handled?
    assert_includes slack_calls_to("chat.postMessage").sole["text"], "(driving items marked handled)"
  end

  test "resolving twice fails and changes nothing" do
    resolve
    result = Incidents::Resolve.call(incident: @incident, actor_name: "Someone else")

    assert_predicate result, :failure?
    assert_equal "Incident #{@incident.id} is already resolved.", result.error
    assert_equal "Ana Every", @incident.reload.resolved_by_name
  end

  test "ends an anomaly attached after the incident was loaded" do
    incident = Incident.includes(anomalies: %i[product source]).find(@incident.id)
    late = create_anomaly!(metric: "volume", dimension: nil)
    late.update!(incident: incident)

    assert_predicate Incidents::Resolve.call(incident: incident, actor_name: "Ana"), :success?
    assert_predicate late.reload, :ended?
  end

  test "sends incident.resolved to subscribed endpoints and keeps anomaly.detected" do
    subscribed = create_webhook_endpoint(events: [ Incident::WEBHOOK_EVENT ], product_ids: [ products(:cora).id ])
    create_webhook_endpoint(events: [ DetectedAnomaly::WEBHOOK_EVENT ])
    create_webhook_endpoint(events: [ Incident::WEBHOOK_EVENT ], product_ids: [ products(:sparkle).id ])

    assert_difference -> { WebhookDelivery.count }, 1 do
      resolve
    end

    delivery = WebhookDelivery.last
    assert_equal subscribed, delivery.webhook_endpoint
    assert_equal "incident.resolved", delivery.event
    payload = delivery.payload
    assert_equal "evt_incident_#{@incident.id}_resolved", payload["id"]
    assert_equal({ "type" => "User", "name" => "Ana Every" }, payload["actor"])
    assert_equal "Fixed the IMAP sync", payload.dig("data", "note")
    assert_equal "resolved", payload.dig("incident", "status")
    assert_equal [ @anomaly.id, @per_source.id ], payload.dig("incident", "anomalies").map { |anomaly| anomaly["id"] }
    assert_includes WebhookEndpoint::EVENTS, DetectedAnomaly::WEBHOOK_EVENT
  end

  test "a Slack user with no happyhappy account is recorded by name" do
    Incidents::Resolve.call(incident: @incident, actor_name: "bingsu")

    assert_nil @incident.reload.resolved_by
    assert_equal "bingsu", @incident.resolved_by_name
  end

  test "resolved spikes leave the dashboard callouts, the feed banner, and the daily overview" do
    zone = Setting.current.digest_zone
    overview = -> { Slack::OverviewMessage.new(Time.current.in_time_zone(zone).to_date, time_zone: zone.name).to_h[:blocks].to_json }
    assert_includes overview.call, "bug messages spiked"
    assert_includes DetectedAnomaly.active, @anomaly

    resolve

    assert_not_includes DetectedAnomaly.active, @anomaly
    assert_not_includes overview.call, "bug messages spiked"
  end
end
