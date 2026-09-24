require "test_helper"

class WebhookEndpointTest < ActiveSupport::TestCase
  include WebhookEndpointHelper

  test "generates a secret and stores it encrypted" do
    endpoint = create_webhook_endpoint

    assert_match(/\Awhsec_\w{40}\z/, endpoint.secret)
    stored = WebhookEndpoint.connection.select_value("SELECT secret FROM webhook_endpoints WHERE id = #{endpoint.id}")
    assert_not_includes stored, endpoint.secret
    assert_equal endpoint.secret, WebhookEndpoint.find(endpoint.id).secret
  end

  test "rotating the secret replaces it" do
    endpoint = create_webhook_endpoint
    old = endpoint.secret

    endpoint.rotate_secret!

    assert_not_equal old, endpoint.reload.secret
  end

  test "requires an https URL outside development" do
    endpoint = WebhookEndpoint.new(name: "Plain", url: "http://hooks.example.com", events: %w[item.arrived])

    assert_not endpoint.valid?
    assert_includes endpoint.errors[:url], "must be an https URL"

    endpoint.url = "not a url"
    assert_not endpoint.valid?
  end

  test "requires at least one known event and known sentiments" do
    endpoint = WebhookEndpoint.new(name: "Empty", url: WEBHOOK_TEST_URL, events: [ "" ])
    assert_not endpoint.valid?
    assert endpoint.errors[:events].any?

    endpoint.events = %w[item.deleted]
    endpoint.sentiments = %w[furious]
    assert_not endpoint.valid?
    assert_match "item.deleted", endpoint.errors[:events].first
    assert_match "furious", endpoint.errors[:sentiments].first
  end

  test "normalizes id filters from form strings" do
    endpoint = create_webhook_endpoint(product_ids: [ "", products(:cora).id.to_s ], category_ids: [ "" ])

    assert_equal [ products(:cora).id ], endpoint.product_ids
    assert_empty endpoint.category_ids
  end
end
