class WebhookDeliveryJob < ApplicationJob
  queue_as :webhooks

  discard_on ActiveJob::DeserializationError

  # Exponential backoff between attempts: 1, 2, 4 ... 64 minutes (about two hours in all).
  def self.backoff(attempts)
    (2**(attempts - 1)).minutes
  end

  def perform(delivery)
    return unless delivery.pending?

    unless delivery.webhook_endpoint.active?
      delivery.update!(status: :failed, last_error: "Endpoint was deactivated before delivery.")
      return
    end

    return if delivery.attempt!

    if delivery.exhausted?
      delivery.failed!
    else
      retry_job(wait: self.class.backoff(delivery.attempts))
    end
  end
end
