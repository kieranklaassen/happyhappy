# frozen_string_literal: true

class ResolveAnomalyTool < ApplicationTool
  tool_name "resolve_anomaly"
  description <<~TEXT.squish
    Resolve the incident behind a bad-news (negative) anomaly, as returned by list_anomalies. Negative
    anomalies of one product that arrive close together share one incident, so this ends all of them, stops
    alerts about those spikes, and posts "Resolved by" under the incident's Slack ping. Add a note saying
    what was done. Set handle_items to also mark the driving items that still need attention handled, with
    the note as the reason. Resolving an incident that is already resolved fails.
  TEXT
  input_schema(
    properties: {
      anomaly_id: { type: "integer", description: "The anomaly id, as returned by list_anomalies." },
      note: { type: "string", description: "Optional: what was done, in plain words." },
      handle_items: { type: "boolean", description: "Also mark the driving items handled. Defaults to false." }
    },
    required: [ "anomaly_id" ]
  )
  annotations(destructive_hint: false, open_world_hint: false)

  def call
    anomaly = DetectedAnomaly.find_by(id: arguments[:anomaly_id]) or raise Error, "Anomaly #{arguments[:anomaly_id]} was not found."
    raise Error, "Anomaly #{anomaly.id} is not bad news, so it has no incident to resolve." unless anomaly.negative?

    result = Incidents::Resolve.call(incident: Incident.for_anomaly!(anomaly), actor: agent,
      note: arguments[:note], handle_items: arguments.fetch(:handle_items, false))
    raise Error, result.error if result.failure?

    { incident: result.incident.to_props }
  end
end
