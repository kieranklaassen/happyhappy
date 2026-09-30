# Marks an incident's Slack ping resolved and threads "Resolved by <name>: <note>" under it.
class PostIncidentResolutionJob < ApplicationJob
  include Slack::Formatting

  queue_as :realtime

  limits_concurrency to: 1, key: ->(incident) { "incident_slack_#{incident.id}" }, duration: 5.minutes
  retry_on Slack::Client::RetryableError, wait: :polynomially_longer, attempts: 10

  def perform(incident)
    incident.reload
    return unless incident.resolved? && incident.slack_posted?

    client = Slack::Client.new
    client.update_message(channel: incident.slack_channel_id, ts: incident.slack_message_ts,
      **Slack::IncidentMessage.new(incident).to_h)
    client.post_message(channel: incident.slack_channel_id, thread_ts: incident.slack_message_ts, text: reply(incident))
  end

  private

  def reply(incident)
    text = ":white_check_mark: Resolved by #{escape(incident.resolved_by_name || "someone")}"
    text += ": #{escape(incident.resolution_note.truncate(QUOTE_LIMIT))}" if incident.resolution_note.present?
    text += " (driving items marked handled)" if incident.items_handled?
    text
  end
end
