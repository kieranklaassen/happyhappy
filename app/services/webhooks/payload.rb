module Webhooks
  # The JSON body of an outbound webhook. Customer-written text is listed in
  # `untrusted_fields` so receivers (often agents) never treat it as instructions.
  class Payload
    UNTRUSTED_FIELDS = %w[item.author.name item.author.handle item.author.email message.body].freeze
    TEST_EVENT = "webhook.test".freeze

    def self.for_event(item_event, event)
      new(item_event, event).to_h
    end

    def self.sample(now: Time.current)
      {
        id: "evt_test_#{SecureRandom.hex(8)}",
        event: TEST_EVENT,
        occurred_at: now.iso8601,
        untrusted_fields: UNTRUSTED_FIELDS,
        actor: { type: nil, name: "happyhappy" },
        data: { note: "Test send from happyhappy. No item changed." },
        item: {
          id: 0, url: "#{base_url}/items/0", status: "new", relevant: true, needs_review: false,
          product: { id: 0, slug: "sample", name: "Sample product", probability: 0.9 },
          category: { id: 0, name: "bug", probability: 0.8 },
          sentiment: { value: "complaint", probability: 0.85 },
          anger_probability: 0.3, claimed_by: nil, permalink: nil,
          source: { id: 0, kind: "slack", name: "Sample source" },
          author: { name: "Sample Customer", handle: "sample_customer", email: nil },
          last_message_at: now.iso8601
        },
        message: { id: 0, body: "This is a sample message.", occurred_at: now.iso8601 }
      }
    end

    # Anomalies carry item ids rather than customer text, so nothing in them is untrusted.
    def self.for_anomaly(anomaly)
      {
        id: "evt_anomaly_#{anomaly.id}_detected",
        event: DetectedAnomaly::WEBHOOK_EVENT,
        occurred_at: anomaly.first_seen_at.iso8601,
        untrusted_fields: [],
        actor: { type: nil, name: "happyhappy" },
        data: {},
        anomaly: anomaly.to_props.merge(
          url: "#{base_url}/items?anomaly=#{anomaly.id}",
          product_url: "#{base_url}/products/#{anomaly.product.slug}/overview"
        )
      }
    end

    def self.base_url
      Rails.application.config.x.public_base_url.presence || "http://localhost:3000"
    end

    def initialize(item_event, event)
      @item_event = item_event
      @event = event
      @item = item_event.item
    end

    def to_h
      {
        # One timeline row can emit two events (a report that moves the item), so the
        # event name is part of the id that receivers dedupe on.
        id: "evt_#{@item_event.id}_#{@event.tr('.', '_')}",
        event: @event,
        occurred_at: @item_event.created_at.iso8601,
        untrusted_fields: UNTRUSTED_FIELDS,
        actor: { type: @item_event.actor_type, name: @item_event.actor_label },
        data: @item_event.data,
        item: item,
        message: message
      }
    end

    private

    def item
      {
        id: @item.id,
        url: "#{self.class.base_url}/items/#{@item.id}",
        status: @item.status,
        relevant: @item.relevant,
        needs_review: @item.needs_review,
        product: @item.product && {
          id: @item.product.id, slug: @item.product.slug, name: @item.product.name,
          probability: @item.product_probability
        },
        category: @item.category && {
          id: @item.category.id, name: @item.category.name, probability: @item.category_probability
        },
        sentiment: @item.sentiment && { value: @item.sentiment, probability: @item.sentiment_probability },
        anger_probability: @item.anger_probability,
        claimed_by: @item.claimed_by_agent&.name,
        permalink: @item.permalink,
        source: { id: @item.source.id, kind: @item.source.kind, name: @item.source.name },
        author: { name: @item.author_name, handle: @item.author_handle, email: @item.author_email },
        last_message_at: @item.last_message_at.iso8601
      }
    end

    def message
      message_id = @item_event.data["message_id"]
      record = (@item.messages.find_by(id: message_id) if message_id) || @item.messages.last
      record && { id: record.id, body: record.body, occurred_at: record.occurred_at.iso8601 }
    end
  end
end
