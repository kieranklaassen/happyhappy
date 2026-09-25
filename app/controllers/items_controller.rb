class ItemsController < InertiaController
  include ItemProps

  PER_PAGE = 50
  MAX_PAGE = 10_000
  HUMAN_STATUSES = Items::ChangeStatus::STATUSES

  def index
    return search if params[:q].present?

    page = params[:page].to_i.clamp(1, MAX_PAGE)
    query = ItemsQuery.from_params(params)
    rows = item_rows(query.call.offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1))

    render inertia: "items/index", props: {
      items: rows.first(PER_PAGE),
      filters: query.filters,
      pagination: { page: page, prev_page: (page - 1 if page > 1), next_page: (page + 1 if rows.size > PER_PAGE) },
      options: feed_options,
      anomalies: DetectedAnomaly.active.includes(:product, :source).recent_first.map(&:to_props),
      search: nil,
      smart: nil,
      error: nil
    }
  rescue ItemsQuery::InvalidFilter => error
    render_invalid_filter(error)
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

  # Feed search (U25). A request without a run id is a new query or a chip
  # change, which ends the searcher's Smart run. Partial reloads of `smart`
  # (TrufflerChannel pings) compute only that prop.
  def search
    query = ItemsQuery.from_params(params)
    removed = Array(params[:removed]).map(&:to_s)
    run_id = params[:run_id].presence
    FeedSearch.cancel(user: Current.user) unless run_id
    result = nil
    keystroke = -> { result ||= FeedSearch.keystroke(params[:q], user: Current.user, filters: query.filters, suppressed: removed) }

    render inertia: "items/index", props: {
      items: -> { ordered_rows(keystroke.call.records.map(&:id)) },
      filters: query.filters,
      pagination: { page: 1, prev_page: nil, next_page: nil },
      options: feed_options,
      anomalies: [],
      search: -> { search_props(keystroke.call, removed, run_id) },
      smart: -> { run_id && smart_props(FeedSearch.find_run(run_id, user: Current.user), query) },
      error: nil
    }
  rescue ItemsQuery::InvalidFilter => error
    render_invalid_filter(error)
  end

  def render_invalid_filter(error)
    render inertia: "items/index", props: {
      items: [], filters: {}, pagination: { page: 1, prev_page: nil, next_page: nil }, options: feed_options,
      anomalies: [], search: nil, smart: nil, error: "That filter is not valid (#{error.message})."
    }
  end

  def search_props(result, removed, run_id)
    {
      query: params[:q].to_s,
      chips: result.chips,
      removed: removed,
      invite_row: result.invite_row,
      encoding_status: result.encoding_status,
      explicit_action: result.explicit_action,
      run_id: run_id
    }
  end

  # Bucket ids load through the feed filters again, so a run can never show
  # an item the searcher's scope has since dropped.
  def smart_props(run, query)
    smart = run.to_h
    visible = query.call.where(id: smart[:buckets].values.flatten.pluck(:id))
    rows = item_rows(visible).index_by { |row| row[:id] }
    buckets = smart[:buckets].transform_values do |entries|
      entries.filter_map { |entry| rows[entry[:id].to_i]&.merge(score: entry[:score]) }
    end
    smart.slice(:run_id, :status, :reserved_slots, :paused, :pending, :collapsed, :no_strong_matches).merge(buckets: buckets)
  end

  def ordered_rows(ids)
    rows = item_rows(Item.where(id: ids)).index_by { |row| row[:id] }
    ids.filter_map { |id| rows[id] }
  end

  def feed_options
    {
      products: Product.ordered.map { |product| product_props(product) },
      categories: Category.ordered.map { |category| category_props(category) },
      sources: Source.ordered.map { |source| source_props(source) },
      sentiments: Item.sentiments.values,
      statuses: Item.statuses.values,
      ranges: ItemsQuery::RANGES.keys,
      actionability: Actionability::BANDS,
      sorts: ItemsQuery::SORTS
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
      actionability: item.actionability,
      actionability_band: item.actionability_band,
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
    message.slice(:id, :body, :occurred_at, :anger_probability, :author_role).merge(
      author: message.author_label,
      sentiment: message.classification_answers&.dig("sentiment", "choice"),
      classified: message.classified?
    )
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
