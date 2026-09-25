require "test_helper"

class WebhookEndpointsControllerTest < ActionDispatch::IntegrationTest
  include WebhookEndpointHelper

  setup do
    sign_in_as users(:one)
    @endpoint = create_webhook_endpoint(events: %w[item.escalated], product_ids: [ products(:cora).id ])
  end

  test "the index lists endpoints with their last delivery and no secrets" do
    @endpoint.deliveries.create!(event: "webhook.test", test: true, status: :failed, last_error: "HTTP 500: nope")

    get webhook_endpoints_path

    assert_response :success
    assert_inertia_component "webhook_endpoints/index"
    row = inertia.props[:endpoints].sole
    assert_equal "Ops hook", row[:name]
    assert_equal %w[item.escalated], row[:events]
    assert_equal "failed", row[:last_delivery][:status]
    assert_not_includes response.body, @endpoint.secret
  end

  test "creating an endpoint generates a secret and shows it on the endpoint page" do
    assert_difference -> { WebhookEndpoint.count } => 1 do
      post webhook_endpoints_path, params: { webhook_endpoint: {
        name: "Support bot", url: "https://bot.example.com/hook", events: %w[item.classified agent.reported],
        product_ids: [ products(:spiral).id ], category_ids: [], sentiments: %w[complaint]
      } }
    end

    endpoint = WebhookEndpoint.find_by!(name: "Support bot")
    assert_redirected_to webhook_endpoint_path(endpoint)
    assert_equal [ products(:spiral).id ], endpoint.product_ids
    assert_equal %w[complaint], endpoint.sentiments

    follow_redirect!
    assert_inertia_component "webhook_endpoints/show"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal endpoint.secret, inertia.props[:endpoint][:secret]
    assert_equal [ "Spiral" ], inertia.props[:filters][:products]
  end

  test "an http URL is refused with an error" do
    assert_no_difference -> { WebhookEndpoint.count } do
      post webhook_endpoints_path, params: { webhook_endpoint: {
        name: "Plain", url: "http://bot.example.com/hook", events: %w[item.classified]
      } }
    end

    assert_redirected_to new_webhook_endpoint_path
    follow_redirect!
    assert_includes inertia.props[:errors][:url], "must be an https URL"
  end

  test "the form offers every event, active products, categories, and sentiments" do
    get new_webhook_endpoint_path

    assert_inertia_component "webhook_endpoints/form"
    assert_equal WebhookEndpoint::EVENTS, inertia.props[:events]
    assert_not_includes inertia.props[:products].map { |product| product[:name] }, "Lex"
    assert_equal Item.sentiments.keys, inertia.props[:sentiments]
    assert_equal %w[item.classified], inertia.props[:endpoint][:events]
  end

  test "updating clears filters and can deactivate" do
    patch webhook_endpoint_path(@endpoint), params: { webhook_endpoint: {
      name: "Ops hook", url: WEBHOOK_TEST_URL, events: %w[item.escalated], product_ids: [ "" ], active: false
    } }

    assert_redirected_to webhook_endpoint_path(@endpoint)
    @endpoint.reload
    assert_empty @endpoint.product_ids
    assert_not @endpoint.active?
  end

  test "the endpoint page lists recent deliveries" do
    @endpoint.deliveries.create!(item_event: item_events(:angry_slack_classified), event: "item.escalated",
      payload: { item: { id: items(:angry_slack).id } }, status: :succeeded, attempts: 1, response_code: 200)

    get webhook_endpoint_path(@endpoint)

    delivery = inertia.props[:deliveries].sole
    assert_equal "succeeded", delivery[:status]
    assert_equal 200, delivery[:response_code]
    assert_equal items(:angry_slack).id, delivery[:item_id]
  end

  test "test send posts a sample event and shows the result" do
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 200)

    post test_send_webhook_endpoint_path(@endpoint)

    assert_redirected_to webhook_endpoint_path(@endpoint)
    assert_equal "Test event delivered (HTTP 200).", flash[:notice]
    delivery = @endpoint.deliveries.first
    assert delivery.test?
    assert delivery.succeeded?
    assert_requested(:post, WEBHOOK_TEST_URL) do |request|
      JSON.parse(request.body)["event"] == "webhook.test" &&
        Webhooks::Signature.verify(@endpoint.secret, request.body, request.headers["X-Happyhappy-Signature"])
    end

    follow_redirect!
    assert_equal "webhook.test", inertia.props[:deliveries].first[:event]
  end

  test "a failed test send shows the error and does not retry" do
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 404, body: "no such hook")

    assert_no_enqueued_jobs do
      post test_send_webhook_endpoint_path(@endpoint)
    end

    assert_equal "Test event failed: HTTP 404: no such hook", flash[:alert]
    assert @endpoint.deliveries.first.failed?
  end

  test "rotating the secret changes it" do
    old = @endpoint.secret

    patch rotate_secret_webhook_endpoint_path(@endpoint)

    assert_redirected_to webhook_endpoint_path(@endpoint)
    assert_not_equal old, @endpoint.reload.secret
  end

  test "deleting an endpoint removes its deliveries" do
    @endpoint.deliveries.create!(event: "webhook.test", test: true)

    assert_difference -> { WebhookEndpoint.count } => -1, -> { WebhookDelivery.count } => -1 do
      delete webhook_endpoint_path(@endpoint)
    end

    assert_redirected_to webhook_endpoints_path
  end

  test "the endpoints screens require sign-in" do
    sign_out

    get webhook_endpoints_path

    assert_redirected_to new_session_path
  end
end
