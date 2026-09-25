class PostAnomalyAlertJob < ApplicationJob
  queue_as :realtime

  retry_on Slack::Client::RetryableError, wait: :polynomially_longer, attempts: 10

  def perform(anomaly)
    return if anomaly.slack_alerted_at?

    setting = Setting.current
    return unless setting.slack_channel?

    Slack::Client.new.post_message(channel: setting.slack_channel_id, **Slack::AnomalyAlertMessage.new(anomaly).to_h)
    anomaly.update!(slack_alerted_at: Time.current)
  end
end
