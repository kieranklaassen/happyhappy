require "test_helper"

class Webhooks::FanOutTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WebhookEndpointHelper

  setup { @item = items(:angry_slack) }

  test "a classified event for a matching product creates one delivery and a signed POST" do
    endpoint = create_webhook_endpoint(events: %w[item.classified], product_ids: [ products(:cora).id ])
    stub_request(:post, WEBHOOK_TEST_URL).to_return(status: 200)

    assert_difference -> { endpoint.deliveries.count } => 1 do
      perform_enqueued_jobs(only: WebhookDeliveryJob) do
        @item.record_event!(:classified, message_id: messages(:angry_slack_first).id)
      end
    end

    delivery = endpoint.deliveries.first
    assert delivery.succeeded?
    assert_equal "item.classified", delivery.event
    assert_requested(:post, WEBHOOK_TEST_URL, times: 1) do |request|
      Webhooks::Signature.verify(endpoint.secret, request.body, request.headers["X-Happyhappy-Signature"])
    end
  end

  test "an endpoint filtered to another product receives nothing" do
    create_webhook_endpoint(product_ids: [ products(:spiral).id ])

    assert_no_difference -> { WebhookDelivery.count } do
      assert_no_enqueued_jobs(only: WebhookDeliveryJob) { @item.record_event!(:classified) }
    end
  end

  test "an inactive endpoint receives nothing" do
    create_webhook_endpoint(active: false)

    assert_no_difference(-> { WebhookDelivery.count }) { @item.record_event!(:arrived) }
  end

  test "an endpoint receives only the events it subscribes to" do
    endpoint = create_webhook_endpoint(events: %w[item.escalated])

    @item.record_event!(:classified)
    assert_equal 0, endpoint.deliveries.count

    @item.record_event!(:escalated, escalation_id: 1)
    assert_equal [ "item.escalated" ], endpoint.deliveries.pluck(:event)
  end

  test "category and sentiment filters must match the item's current labels" do
    matching = create_webhook_endpoint(name: "Bugs", category_ids: [ categories(:bug).id ], sentiments: %w[complaint])
    other_category = create_webhook_endpoint(name: "Billing", category_ids: [ categories(:billing).id ])
    other_sentiment = create_webhook_endpoint(name: "Praise", sentiments: %w[praise])

    @item.record_event!(:classified)

    assert_equal 1, matching.deliveries.count
    assert_equal 0, other_category.deliveries.count
    assert_equal 0, other_sentiment.deliveries.count
  end

  test "claims, releases, and status changes all send item.status_changed" do
    endpoint = create_webhook_endpoint(events: %w[item.status_changed])

    @item.record_event!(:claimed, actor: agents(:cursor), from: "new", to: "claimed")
    @item.record_event!(:released, actor: agents(:cursor))
    @item.change_status!(:handled, actor: users(:one))

    assert_equal [ "item.status_changed" ] * 3, endpoint.deliveries.pluck(:event)
  end

  test "a report that changes status sends agent.reported and item.status_changed" do
    endpoint = create_webhook_endpoint(events: %w[agent.reported item.status_changed])

    @item.record_event!(:reported, actor: agents(:cursor), summary: "Refunded", link: nil, status: "handled",
      from: "in_progress")
    @item.record_event!(:reported, actor: agents(:cursor), summary: "Still on it", link: nil,
      status: "in_progress", from: "in_progress")

    assert_equal %w[agent.reported item.status_changed agent.reported].sort, endpoint.deliveries.pluck(:event).sort
  end

  test "the payload carries the item as the event left it, not as it was before" do
    endpoint = create_webhook_endpoint(events: %w[item.status_changed])

    Agents::Claim.call(agent: agents(:cursor), item: @item)

    payload = endpoint.deliveries.first.payload
    assert_equal "claimed", payload.dig("item", "status")
    assert_equal agents(:cursor).name, payload.dig("item", "claimed_by")
  end

  test "timeline kinds without a webhook event send nothing" do
    create_webhook_endpoint

    assert_no_difference(-> { WebhookDelivery.count }) { @item.record_event!(:overdue, agent_id: 1) }
  end

  test "a fan-out failure is reported and never fails the timeline event" do
    create_webhook_endpoint
    reported = []
    subscriber = Class.new { define_method(:report) { |error, **| reported << error } }.new
    Rails.error.subscribe(subscriber)
    original = Webhooks::FanOut.method(:call)
    Webhooks::FanOut.define_singleton_method(:call) { |_| raise "boom" }

    event = @item.record_event!(:arrived)

    assert event.persisted?
    assert_equal [ "boom" ], reported.map(&:message)
  ensure
    Webhooks::FanOut.define_singleton_method(:call, original) if original
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  test "the payload carries the item with labels and permalink and marks customer text untrusted" do
    endpoint = create_webhook_endpoint(events: %w[item.classified])
    message = messages(:angry_slack_first)

    @item.record_event!(:classified, message_id: message.id)

    payload = endpoint.deliveries.first.payload
    assert_equal "item.classified", payload["event"]
    assert_equal @item.id, payload.dig("item", "id")
    assert_equal "cora", payload.dig("item", "product", "slug")
    assert_equal "bug", payload.dig("item", "category", "name")
    assert_equal "complaint", payload.dig("item", "sentiment", "value")
    assert_equal @item.permalink, payload.dig("item", "permalink")
    assert_match %r{/items/#{@item.id}\z}, payload.dig("item", "url")
    assert_equal message.body, payload.dig("message", "body")
    assert_includes payload["untrusted_fields"], "message.body"
    assert_includes payload["untrusted_fields"], "item.author.handle"
  end
end
