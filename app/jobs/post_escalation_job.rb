class PostEscalationJob < ApplicationJob
  queue_as :realtime

  retry_on Slack::Client::RetryableError, wait: :polynomially_longer, attempts: 10

  def perform(escalation)
    return if escalation.posted?

    ts = Slack::Client.new.post_message(channel: escalation.slack_channel_id,
      **Slack::EscalationMessage.new(escalation).to_h)

    escalation.transaction do
      escalation.update!(slack_message_ts: ts, posted_at: Time.current, last_error: nil)
      escalation.item.record_event!(:escalated, escalation_id: escalation.id,
        slack_channel_id: escalation.slack_channel_id, slack_message_ts: ts)
    end
  rescue Slack::Client::Error => error
    escalation.update!(last_error: error.message)
    raise
  end
end
