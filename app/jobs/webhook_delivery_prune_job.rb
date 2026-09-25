class WebhookDeliveryPruneJob < ApplicationJob
  queue_as :default

  def perform
    WebhookDelivery.expired.in_batches(of: 1_000).delete_all
  end
end
