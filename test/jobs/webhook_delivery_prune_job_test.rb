require "test_helper"

class WebhookDeliveryPruneJobTest < ActiveJob::TestCase
  include WebhookEndpointHelper

  test "deletes deliveries older than 30 days and keeps newer ones" do
    endpoint = create_webhook_endpoint
    old = endpoint.deliveries.create!(event: "webhook.test", test: true, created_at: 31.days.ago)
    recent = endpoint.deliveries.create!(event: "webhook.test", test: true, created_at: 29.days.ago)

    WebhookDeliveryPruneJob.perform_now

    assert_not WebhookDelivery.exists?(old.id)
    assert WebhookDelivery.exists?(recent.id)
  end

  test "each environment prunes webhook deliveries daily" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)

    %w[production development test].each do |env|
      assert_equal "WebhookDeliveryPruneJob", recurring.fetch(env).fetch("webhook_delivery_prune").fetch("class")
    end
  end
end
