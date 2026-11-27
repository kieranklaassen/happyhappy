require "test_helper"

class IncidentTest < ActiveSupport::TestCase
  include AnomalyHelper

  test "validates status enum and required timestamps" do
    now = Time.current
    incident = Incident.new(product: products(:cora), opened_at: now, last_anomaly_at: now)
    assert incident.valid?, incident.errors.full_messages.to_sentence
    assert_equal %w[open resolved], Incident.statuses.keys

    incident.status = "resolved"
    assert incident.valid?

    invalid = Incident.new(product: products(:cora), status: "closed", opened_at: nil, last_anomaly_at: nil)
    refute invalid.valid?
    %i[status opened_at last_anomaly_at].each do |attr|
      assert invalid.errors.key?(attr), "expected validation error on #{attr}"
    end
  end

  test "recent_first orders by opened_at descending and breaks ties by id descending" do
    now = Time.current.change(usec: 0)
    older = Incident.create!(product: products(:cora), opened_at: now - 2.hours, last_anomaly_at: now - 1.hour)
    tie_first = Incident.create!(product: products(:cora), opened_at: now, last_anomaly_at: now)
    tie_second = Incident.create!(product: products(:cora), opened_at: now, last_anomaly_at: now)

    assert_equal [ tie_second, tie_first, older ], Incident.recent_first.to_a
  end

  test "for_anomaly! creates and links a new incident when the anomaly has none" do
    first_seen = 20.minutes.ago.change(usec: 0)
    last_seen = 5.minutes.ago.change(usec: 0)
    anomaly = create_anomaly!(first_seen_at: first_seen, last_seen_at: last_seen)

    incident = assert_difference -> { Incident.count }, 1 do
      Incident.for_anomaly!(anomaly)
    end

    assert_predicate incident, :open?
    assert_equal anomaly.product, incident.product
    assert_equal first_seen, incident.opened_at
    assert_equal last_seen, incident.last_anomaly_at
    assert_equal incident, anomaly.reload.incident
  end

  test "for_anomaly! returns the existing incident without creating a new one" do
    anomaly = create_anomaly!
    existing = Incident.for_anomaly!(anomaly)

    returned = assert_no_difference -> { Incident.count } do
      Incident.for_anomaly!(anomaly.reload)
    end

    assert_equal existing, returned
  end

  test "url defaults to localhost and strips trailing slashes from PUBLIC_BASE_URL" do
    now = Time.current
    incident = Incident.create!(product: products(:cora), opened_at: now, last_anomaly_at: now)

    with_env("PUBLIC_BASE_URL", nil) do
      assert_equal "http://localhost:3000/incidents/#{incident.id}", incident.url
    end

    with_env("PUBLIC_BASE_URL", "https://happyhappy.every.to") do
      assert_equal "https://happyhappy.every.to/incidents/#{incident.id}", incident.url
    end

    with_env("PUBLIC_BASE_URL", "https://happyhappy.every.to/") do
      assert_equal "https://happyhappy.every.to/incidents/#{incident.id}", incident.url
    end
  end

  test "slack_posted? requires both channel id and message ts" do
    now = Time.current
    incident = Incident.new(product: products(:cora), opened_at: now, last_anomaly_at: now)

    refute incident.slack_posted?

    incident.slack_channel_id = "C0AGCDCD6KG"
    refute incident.slack_posted?

    incident.slack_channel_id = nil
    incident.slack_message_ts = "1727200000.000100"
    refute incident.slack_posted?

    incident.slack_channel_id = "C0AGCDCD6KG"
    assert incident.slack_posted?
  end

  test "item_ids returns driving item ids from the most recent anomaly first, deduplicated" do
    now = Time.current
    incident = Incident.create!(product: products(:cora), opened_at: now - 1.hour, last_anomaly_at: now)

    first = create_anomaly!(
      incident: incident,
      item_ids: [ items(:angry_slack).id, items(:claimed_intercom).id ]
    )
    second = create_anomaly!(
      incident: incident,
      metric: "volume",
      dimension: nil,
      item_ids: [ items(:claimed_intercom).id, items(:handled_email).id ]
    )

    assert_equal [ first, second ], incident.anomalies.to_a
    assert_equal [ items(:claimed_intercom).id, items(:handled_email).id, items(:angry_slack).id ], incident.item_ids
  end

  test "sources combines anomaly sources and item sources, deduplicated and ordered by name" do
    now = Time.current
    incident = Incident.create!(product: products(:cora), opened_at: now - 1.hour, last_anomaly_at: now)

    create_anomaly!(
      incident: incident,
      source: sources(:discord_spiral),
      item_ids: [ items(:angry_slack).id ]
    )
    create_anomaly!(
      incident: incident,
      source: sources(:slack_community),
      metric: "volume",
      dimension: nil,
      item_ids: [ items(:claimed_intercom).id, items(:angry_slack).id ]
    )

    assert_equal(
      [ sources(:slack_community), sources(:intercom_inbox), sources(:discord_spiral) ],
      incident.sources
    )
  end

  test "to_props serializes incident details, sources, nested anomalies, and resolved fields" do
    opened_at = Time.zone.parse("2026-06-15 12:00:00 UTC")
    last_anomaly_at = Time.zone.parse("2026-06-15 12:30:00 UTC")
    resolved_at = Time.zone.parse("2026-06-15 13:00:00 UTC")
    cora = products(:cora)

    incident = Incident.create!(
      product: cora,
      opened_at: opened_at,
      last_anomaly_at: last_anomaly_at
    )
    anomaly = create_anomaly!(
      product: cora,
      incident: incident,
      source: sources(:slack_community),
      item_ids: [ items(:angry_slack).id, items(:claimed_intercom).id ]
    )

    with_env("PUBLIC_BASE_URL", "https://happyhappy.every.to/") do
      open_props = incident.to_props
      assert_equal(
        {
          id: incident.id,
          product: { id: cora.id, slug: cora.slug, name: cora.name },
          status: "open",
          opened_at: opened_at.iso8601,
          last_anomaly_at: last_anomaly_at.iso8601,
          resolved_at: nil,
          resolved_by: nil,
          resolution_note: nil,
          items_handled: false,
          item_ids: [ items(:angry_slack).id, items(:claimed_intercom).id ],
          sources: [
            {
              id: sources(:slack_community).id,
              kind: sources(:slack_community).kind,
              name: sources(:slack_community).name
            },
            {
              id: sources(:intercom_inbox).id,
              kind: sources(:intercom_inbox).kind,
              name: sources(:intercom_inbox).name
            }
          ],
          slack_posted: false,
          url: "https://happyhappy.every.to/incidents/#{incident.id}",
          anomalies: [ anomaly.to_props ]
        },
        open_props
      )

      incident.update!(
        status: "resolved",
        resolved_at: resolved_at,
        resolved_by: users(:every_ana),
        resolved_by_name: "Ana Every",
        resolution_note: "Restarted sync worker",
        items_handled: true,
        slack_channel_id: "C0AGCDCD6KG",
        slack_message_ts: "1727200000.000100"
      )

      resolved_props = incident.to_props
      assert_equal "resolved", resolved_props[:status]
      assert_equal resolved_at.iso8601, resolved_props[:resolved_at]
      assert_equal "Ana Every", resolved_props[:resolved_by]
      assert_equal "Restarted sync worker", resolved_props[:resolution_note]
      assert_equal true, resolved_props[:items_handled]
      assert_equal true, resolved_props[:slack_posted]
    end
  end

  test "destroying an incident nullifies incident_id on its anomalies" do
    anomaly = create_anomaly!
    incident = Incident.for_anomaly!(anomaly)

    assert_no_difference -> { DetectedAnomaly.count } do
      incident.destroy!
    end

    assert_nil anomaly.reload.incident_id
  end

  private

  def with_env(key, value)
    had_key = ENV.key?(key)
    previous = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    had_key ? ENV[key] = previous : ENV.delete(key)
  end
end
