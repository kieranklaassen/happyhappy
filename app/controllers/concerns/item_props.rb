# Hand-written props for item lists (the feed and the product overview's notable items).
module ItemProps
  extend ActiveSupport::Concern

  EXCERPT_LENGTH = 280

  private

  def item_rows(items)
    items = items.includes(:product, :category, :source, :claimed_by_agent).to_a
    ranked = Message.from_customers.where(item_id: items.map(&:id))
      .select(:item_id, :body, "ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY occurred_at DESC, id DESC) AS position")
    latest_bodies = Message.from(ranked, :messages).where(position: 1).pluck(:item_id, :body).to_h

    items.map do |item|
      {
        id: item.id,
        excerpt: latest_bodies[item.id].to_s.squish.truncate(EXCERPT_LENGTH),
        author: author_label(item),
        source: source_props(item.source),
        product: product_props(item.product),
        category: category_props(item.category),
        sentiment: item.sentiment,
        status: item.status,
        relevant: item.relevant,
        needs_review: item.needs_review,
        overdue: item.overdue,
        claimed_by: item.claimed_by_agent&.name,
        anger_probability: item.anger_probability,
        actionability: item.actionability,
        actionability_band: item.actionability_band,
        last_message_at: item.last_message_at
      }
    end
  end

  def author_label(item)
    item.author_handle.presence || item.author_name.presence || item.author_email.presence || "unknown"
  end

  def source_props(source)
    source.slice(:id, :name, :kind)
  end

  def product_props(product)
    product && { id: product.id, name: product.name, slug: product.slug, retired: product.retired? }
  end

  def category_props(category)
    category && { id: category.id, name: category.name, retired: category.retired? }
  end
end
