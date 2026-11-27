require "test_helper"

class WebhookDeliveryTest < ActiveSupport::TestCase
  include WebhookEndpointHelper

  setup do
    @endpoint = create_webhook_endpoint
  end

  test "validates status enum values" do
    delivery = build_delivery
    assert_equal "pending", delivery.status

    %w[pending succeeded failed].each do |status|
      delivery.status = status
      assert delivery.valid?, "expected status #{status.inspect} to be valid"
    end

    delivery.status = "retrying"
    assert_not delivery.valid?
    assert delivery.errors.key?(:status)
  end

  test "validates event against known webhook events and test event" do
    (WebhookEndpoint::EVENTS + [ Webhooks::Payload::TEST_EVENT ]).each do |event|
      delivery = build_delivery(event: event)
      assert delivery.valid?, "expected event #{event.inspect} to be valid"
    end

    [ "item.deleted", "", nil ].each do |event|
      delivery = build_delivery(event: event)
      assert_not delivery.valid?, "expected event #{event.inspect} to be invalid"
      assert delivery.errors.key?(:event)
    end
  end

  test "requires webhook_endpoint and allows optional item_event" do
    without_item_event = build_delivery(item_event: nil)
    assert without_item_event.valid?

    without_endpoint = build_delivery(webhook_endpoint: nil)
    assert_not without_endpoint.valid?
    assert without_endpoint.errors.key?(:webhook_endpoint)
  end

  test "expired includes only deliveries created strictly before retention cutoff" do
    freeze_time do
      cutoff = WebhookDelivery::RETENTION.ago
      expired = create_delivery(created_at: cutoff - 1.second)
      at_cutoff = create_delivery(created_at: cutoff)
      recent = create_delivery(created_at: cutoff + 1.second)

      assert_equal [ expired ], WebhookDelivery.expired.to_a
      assert_not_includes WebhookDelivery.expired, at_cutoff
      assert_not_includes WebhookDelivery.expired, recent
    end
  end

  test "exhausted? is false below MAX_ATTEMPTS and true at and above MAX_ATTEMPTS" do
    assert_not WebhookDelivery.new(attempts: 0).exhausted?
    assert_not WebhookDelivery.new(attempts: WebhookDelivery::MAX_ATTEMPTS - 1).exhausted?
    assert WebhookDelivery.new(attempts: WebhookDelivery::MAX_ATTEMPTS).exhausted?
    assert WebhookDelivery.new(attempts: WebhookDelivery::MAX_ATTEMPTS + 1).exhausted?
  end

  test "attempt! sends a signed JSON POST and records success on 2xx responses" do
    now = Time.current.change(usec: 0)
    delivery = create_delivery(
      attempts: 1,
      response_code: 500,
      last_error: "HTTP 500: prior failure",
      payload: { "id" => "evt_1", "event" => "item.classified" }
    )
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 204)

    assert delivery.attempt!(now: now)

    assert_requested(:post, WEBHOOK_TEST_URL, times: 1) do |request|
      assert_equal delivery.payload.to_json, request.body
      assert_equal "application/json; charset=utf-8", request.headers["Content-Type"]
      assert_equal "happyhappy-webhooks", request.headers["User-Agent"]
      assert_equal delivery.event, request.headers["X-Happyhappy-Event"]
      assert_equal delivery.id.to_s, request.headers["X-Happyhappy-Delivery"]
      expected_signature = Webhooks::Signature.sign(@endpoint.secret, request.body, time: now)
      assert_equal expected_signature, request.headers[Webhooks::Signature::HEADER]
      assert Webhooks::Signature.verify(@endpoint.secret, request.body, expected_signature, now: now)
    end

    delivery.reload
    assert delivery.succeeded?
    assert_equal 2, delivery.attempts
    assert_equal now, delivery.last_attempted_at
    assert_equal 204, delivery.response_code
    assert_nil delivery.last_error
  end

  test "attempt! records HTTP error details and keeps status unchanged on non-2xx responses" do
    now = Time.current.change(usec: 0)
    delivery = create_delivery
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 422, body: "unprocessable payload")

    assert_not delivery.attempt!(now: now)

    delivery.reload
    assert delivery.pending?
    assert_equal 1, delivery.attempts
    assert_equal now, delivery.last_attempted_at
    assert_equal 422, delivery.response_code
    assert_equal "HTTP 422: unprocessable payload", delivery.last_error
  end

  test "attempt! scrubs invalid UTF-8 and squishes whitespace in non-2xx response bodies" do
    now = Time.current.change(usec: 0)
    delivery = create_delivery
    raw_body = "  bad\xFF\xFE  \n\t  payload  ".b
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 500, body: raw_body)

    assert_not delivery.attempt!(now: now)

    delivery.reload
    assert delivery.last_error.valid_encoding?
    assert_equal "HTTP 500: bad\uFFFD\uFFFD payload", delivery.last_error
  end

  test "attempt! falls back to HTTP status message when non-2xx response body is blank" do
    now = Time.current.change(usec: 0)
    delivery = create_delivery
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: [ 502, "Bad Gateway" ], body: "   \n\t  ")

    assert_not delivery.attempt!(now: now)

    delivery.reload
    assert delivery.pending?
    assert_equal 502, delivery.response_code
    assert_equal "HTTP 502: Bad Gateway", delivery.last_error
  end

  test "attempt! truncates long non-2xx error bodies to ERROR_BODY_LIMIT" do
    now = Time.current.change(usec: 0)
    delivery = create_delivery
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 500, body: "x" * (WebhookDelivery::ERROR_BODY_LIMIT + 100))

    assert_not delivery.attempt!(now: now)

    delivery.reload
    assert_equal WebhookDelivery::ERROR_BODY_LIMIT, delivery.last_error.length
    assert delivery.last_error.start_with?("HTTP 500: ")
    assert delivery.last_error.end_with?("...")
  end

  test "attempt! records network failures, clears response_code, and truncates long messages" do
    now = Time.current.change(usec: 0)
    delivery = create_delivery(response_code: 500)
    stub_request(:post, WEBHOOK_TEST_URL).to_raise(Errno::ECONNREFUSED.new("connect(2)"))

    assert_not delivery.attempt!(now: now)

    delivery.reload
    assert delivery.pending?
    assert_equal 1, delivery.attempts
    assert_equal now, delivery.last_attempted_at
    assert_nil delivery.response_code
    assert_equal "Errno::ECONNREFUSED: #{Errno::ECONNREFUSED.new("connect(2)").message}", delivery.last_error

    later = now + 1.minute
    stub_request(:post, WEBHOOK_TEST_URL).to_raise(Net::OpenTimeout.new("t" * (WebhookDelivery::ERROR_BODY_LIMIT + 100)))

    assert_not delivery.attempt!(now: later)

    delivery.reload
    assert delivery.pending?
    assert_equal 2, delivery.attempts
    assert_equal later, delivery.last_attempted_at
    assert_nil delivery.response_code
    assert_equal WebhookDelivery::ERROR_BODY_LIMIT, delivery.last_error.length
    assert delivery.last_error.start_with?("Net::OpenTimeout: ")
    assert delivery.last_error.end_with?("...")
  end

  test "attempt! delivers to both http and https endpoint URLs" do
    now = Time.current.change(usec: 0)
    http_url = "http://hooks.example.com/plain"
    http_endpoint = create_webhook_endpoint
    http_endpoint.update_column(:url, http_url)

    stub_request(:post, http_url).to_return(status: 200)
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 200)

    http_delivery = create_delivery(webhook_endpoint: http_endpoint)
    https_delivery = create_delivery

    assert http_delivery.attempt!(now: now)
    assert https_delivery.attempt!(now: now)

    assert_requested(:post, http_url, times: 1)
    assert_requested(:post, WEBHOOK_TEST_URL, times: 1)
    assert http_delivery.reload.succeeded?
    assert https_delivery.reload.succeeded?
  end

  private

  def build_delivery(**attributes)
    WebhookDelivery.new({
      webhook_endpoint: @endpoint,
      event: "item.classified",
      payload: { "event" => "item.classified" }
    }.merge(attributes))
  end

  def create_delivery(**attributes)
    build_delivery(**attributes).tap(&:save!)
  end
end
