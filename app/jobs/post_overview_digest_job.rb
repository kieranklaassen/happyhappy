class PostOverviewDigestJob < ApplicationJob
  queue_as :default

  retry_on Slack::Client::RetryableError, wait: :polynomially_longer, attempts: 10

  def perform(digest)
    return if digest.posted?

    setting = Setting.current
    return unless setting.slack_channel?

    message = Slack::OverviewMessage.new(digest.date.yesterday, time_zone: setting.digest_time_zone)
    ts = Slack::Client.new.post_message(channel: setting.slack_channel_id, **message.to_h)
    digest.update!(slack_message_ts: ts, posted_at: Time.current, last_error: nil)
  rescue Slack::Client::Error => error
    digest.update!(last_error: error.message)
    raise
  end
end
