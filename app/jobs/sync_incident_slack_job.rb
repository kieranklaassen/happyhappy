# Posts an incident's ping to its product's alert channel, or updates the one already posted as
# anomalies join, so one incident is always one top-level Slack message.
class SyncIncidentSlackJob < ApplicationJob
  queue_as :realtime

  limits_concurrency to: 1, key: ->(incident) { "incident_slack_#{incident.id}" }, duration: 5.minutes
  retry_on Slack::Client::RetryableError, wait: :polynomially_longer, attempts: 10

  def perform(incident)
    incident.reload
    message = Slack::IncidentMessage.new(incident).to_h
    client = Slack::Client.new

    if incident.slack_posted?
      client.update_message(channel: incident.slack_channel_id, ts: incident.slack_message_ts, **message)
    elsif incident.open? && (channel = incident.product.alert_channel_id)
      ts = client.post_message_joining(channel: channel, **message)
      incident.update!(slack_channel_id: channel, slack_message_ts: ts)
    end
  end
end
