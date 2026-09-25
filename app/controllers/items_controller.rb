class ItemsController < InertiaController
  include ItemProps

  PER_PAGE = 50
  MAX_PAGE = 10_000
  HUMAN_STATUSES = Items::ChangeStatus::STATUSES

  def index
    page = params[:page].to_i.clamp(1, MAX_PAGE)
    query = ItemsQuery.from_params(params)
    rows = item_rows(query.call.offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1))

    render inertia: "items/index", props: {
      items: rows.first(PER_PAGE),
      filters: query.filters,
      pagination: { page: page, prev_page: (page - 1 if page > 1), next_page: (page + 1 if rows.size > PER_PAGE) },
      options: feed_options,
      anomalies: DetectedAnomaly.active.includes(:product, :source).recent_first.map(&:to_props),
      error: nil
    }
  rescue ItemsQuery::InvalidFilter => error
    render inertia: "items/index", props: {
      items: [], filters: {}, pagination: { page: 1, prev_page: nil, next_page: nil }, options: feed_options,
      anomalies: [], error: "That filter is not valid (#{error.message})."
    }
  end

  def show
    item = Item.includes(:product, :category, :source, :claimed_by_agent, :messages).find(params[:id])

    render inertia: "items/show", props: {
      item: item_detail(item),
      messages: item.messages.map { |message| message_props(message) },
      events: item.events.includes(:actor).map { |event| event_props(event) },
      options: {
        products: selectable(Product, item.product).map { |product| product_props(product) },
        categories: selectable(Category, item.category).map { |category| category_props(category) },
        sentiments: Item.sentiments.values,
        statuses: HUMAN_STATUSES
      },
      low_confidence_threshold: Setting.current.low_confidence_threshold
    }
  end

  private

  def feed_options
    {
      products: Product.ordered.map { |product| product_props(product) },
      categories: Category.ordered.map { |category| category_props(category) },
      sources: Source.ordered.map { |source| source_props(source) },
      sentiments: Item.sentiments.values,
      statuses: Item.statuses.values,
      ranges: ItemsQuery::RANGES.keys
    }
  end

  def selectable(model, current)
    model.active.or(model.where(id: current&.id)).ordered
  end

  def item_detail(item)
    {
      id: item.id,
      author: author_label(item),
      author_name: item.author_name,
      author_email: item.author_email,
      permalink: item.permalink,
      source: source_props(item.source),
      status: item.status,
      needs_review: item.needs_review,
      overdue: item.overdue,
      claimed_by: item.claimed_by_agent&.name,
      claimed_at: item.claimed_at,
      last_reported_at: item.last_reported_at,
      last_message_at: item.last_message_at,
      anger_probability: item.anger_probability,
      labels: {
        product: label(product_props(item.product), item.product_probability, item.product_human_set),
        category: label(category_props(item.category), item.category_probability, item.category_human_set),
        sentiment: label(item.sentiment, item.sentiment_probability, item.sentiment_human_set),
        relevant: label(item.relevant, item.relevance_probability, item.relevant_human_set)
      }
    }
  end

  def label(value, probability, human_set)
    { value: value, probability: probability, human_set: human_set }
  end

  def message_props(message)
    message.slice(:id, :body, :occurred_at, :anger_probability).merge(classified: message.classified?)
  end

  def event_props(event)
    {
      id: event.id,
      kind: event.kind,
      actor: { type: event.actor_type, name: event.actor_label },
      data: event.data,
      created_at: event.created_at
    }
  end
end
