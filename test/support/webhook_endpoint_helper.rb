# Builds outbound webhook endpoints for tests; endpoint URLs are stubbed with
# webmock, never reached.
#
#   endpoint = create_webhook_endpoint(events: %w[item.classified], product_ids: [ products(:cora).id ])
#   stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 200)
module WebhookEndpointHelper
  WEBHOOK_TEST_URL = "https://hooks.example.com/happyhappy".freeze

  def create_webhook_endpoint(**attributes)
    WebhookEndpoint.create!({ name: "Ops hook", url: WEBHOOK_TEST_URL, events: WebhookEndpoint::EVENTS }.merge(attributes))
  end
end
