class PostDigestJob < ApplicationJob
  queue_as :default

  retry_on Slack::Client::RetryableError, wait: :polynomially_longer, attempts: 10

  def perform(digest)
    return if digest.posted?

    message = Slack::DigestMessage.new(digest.product, digest.date.yesterday)
    ts = Slack::Client.new.post_message(channel: digest.product.slack_channel_id, **message.to_h)
    digest.update!(slack_message_ts: ts, posted_at: Time.current, last_error: nil)
  rescue Slack::Client::Error => error
    digest.update!(last_error: error.message)
    raise
  end
end
