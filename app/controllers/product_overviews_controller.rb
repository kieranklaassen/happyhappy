class ProductOverviewsController < InertiaController
  include ItemProps

  DAYS = 30
  NOTABLE_LIMIT = 3

  def show
    product = Product.find_by(slug: params[:product_id]) || Product.find(params[:product_id])
    first_day = (DAYS - 1).days.ago.to_date
    items = product.items.relevant.where(created_at: first_day.beginning_of_day..)

    render inertia: "products/overview", props: {
      product: product_props(product),
      days: daily_counts(items, first_day),
      totals: totals(items),
      notable_complaints: item_rows(items.complaint.order(anger_probability: :desc, id: :desc).limit(NOTABLE_LIMIT)),
      notable_praise: item_rows(items.praise.order(sentiment_probability: :desc, id: :desc).limit(NOTABLE_LIMIT)),
      products: Product.ordered.map { |other| product_props(other) }
    }
  end

  private

  def daily_counts(items, first_day)
    by_day = items.pluck(:created_at, :sentiment).group_by { |created_at, _| created_at.in_time_zone.to_date }

    (first_day..Date.current).map do |day|
      sentiments = by_day.fetch(day, []).map(&:last)
      { date: day.iso8601, **sentiment_counts(sentiments) }
    end
  end

  def totals(items)
    sentiment_counts(items.pluck(:sentiment))
  end

  def sentiment_counts(sentiments)
    tally = sentiments.tally
    Item.sentiments.values.to_h { |sentiment| [ sentiment.to_sym, tally.fetch(sentiment, 0) ] }
      .merge(total: sentiments.size)
  end
end
