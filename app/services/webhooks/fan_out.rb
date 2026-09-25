module Webhooks
  # Turns one new timeline event into one delivery per matching endpoint and
  # enqueues each (KTD19). Called after the event's transaction commits.
  #
  #   Webhooks::FanOut.call(item_event) # => [WebhookDelivery, ...]
  class FanOut
    EVENTS_BY_KIND = {
      "arrived" => %w[item.arrived],
      "classified" => %w[item.classified],
      "status_changed" => %w[item.status_changed],
      "claimed" => %w[item.status_changed],
      "released" => %w[item.status_changed],
      "reassigned" => %w[item.status_changed],
      "escalated" => %w[item.escalated],
      "reported" => %w[agent.reported]
    }.freeze

    def self.call(item_event)
      new(item_event).call
    end

    def self.events_for(item_event)
      events = EVENTS_BY_KIND.fetch(item_event.kind, [])
      # A report that moves the item (for example to handled) is also a status change.
      if item_event.reported? && item_event.data["status"].present? && item_event.data["status"] != item_event.data["from"]
        events += %w[item.status_changed]
      end
      events
    end

    def initialize(item_event)
      @item_event = item_event
    end

    def call
      events = self.class.events_for(@item_event)
      return [] if events.empty?

      endpoints = WebhookEndpoint.active.to_a
      return [] if endpoints.empty?

      # Claims, releases, and reports write the item with update_all, so the event's
      # cached parent still holds the pre-event status and holder.
      item = @item_event.reload_item
      events.flat_map do |event|
        matching = endpoints.select { |endpoint| endpoint.subscribed?(event) && endpoint.matches?(item) }
        next [] if matching.empty?

        payload = Payload.for_event(@item_event, event)
        matching.map { |endpoint| enqueue(endpoint, event, payload) }
      end
    end

    private

    def enqueue(endpoint, event, payload)
      delivery = endpoint.deliveries.create!(item_event: @item_event, event: event, payload: payload)
      WebhookDeliveryJob.perform_later(delivery)
      delivery
    end
  end
end
