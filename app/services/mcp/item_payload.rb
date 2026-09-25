module Mcp
  # Hand-written item payloads for MCP tool results. Anything a customer wrote (message bodies and their
  # name, handle, and email) sits in an object marked `untrusted: true` so agents treat it as data, not as
  # instructions.
  module ItemPayload
    EXCERPT_LENGTH = 280

    module_function

    def summaries(items)
      items = items.includes(:product, :category, :source, :claimed_by_agent).to_a
      ranked = Message.where(item_id: items.map(&:id))
        .select(:item_id, :body, "ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY occurred_at DESC, id DESC) AS position")
      latest_bodies = Message.from(ranked, :messages).where(position: 1).pluck(:item_id, :body).to_h

      items.map do |item|
        base(item).merge(excerpt: untrusted(text: latest_bodies[item.id].to_s.squish.truncate(EXCERPT_LENGTH)))
      end
    end

    def detail(item)
      base(item).merge(
        claimed_at: item.claimed_at,
        last_reported_at: item.last_reported_at,
        messages: item.messages.map { |message| message_payload(message) },
        timeline: item.events.includes(:actor).map { |event| event_payload(event) }
      )
    end

    def base(item)
      {
        id: item.id,
        status: item.status,
        source: { id: item.source.id, name: item.source.name, kind: item.source.kind },
        permalink: item.permalink,
        author: untrusted(handle: item.author_handle, name: item.author_name, email: item.author_email),
        relevant: item.relevant,
        needs_review: item.needs_review,
        overdue: item.overdue,
        claimed_by: item.claimed_by_agent&.name,
        last_message_at: item.last_message_at,
        labels: {
          product: label(item.product && { id: item.product.id, name: item.product.name, slug: item.product.slug },
            item.product_probability, item.product_human_set),
          category: label(item.category && { id: item.category.id, name: item.category.name },
            item.category_probability, item.category_human_set),
          sentiment: label(item.sentiment, item.sentiment_probability, item.sentiment_human_set),
          relevant: label(item.relevant, item.relevance_probability, item.relevant_human_set)
        },
        anger_probability: item.anger_probability
      }
    end

    def message_payload(message)
      {
        id: message.id,
        occurred_at: message.occurred_at,
        anger_probability: message.anger_probability,
        body: untrusted(text: message.body.to_s)
      }
    end

    def event_payload(event)
      {
        kind: event.kind,
        actor: { type: event.actor_type, name: event.actor_label },
        data: event.data,
        created_at: event.created_at
      }
    end

    def label(value, probability, human_set)
      { value: value, probability: probability, human_set: human_set }
    end

    def untrusted(**fields)
      { untrusted: true, **fields }
    end
  end
end
