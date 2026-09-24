# Filters the item feed. The team feed (ItemsController) and the MCP tools share it, so both see the
# same items for the same filters.
#
#   ItemsQuery.new(product: "cora", sentiment: "complaint", range: "7d").call  # => Item relation
#   ItemsQuery.from_params(params)                                          # request params, extra keys ignored
#
# Every filter is optional and a blank value means "no filter". List filters take one value or an array
# and match any of them.
#
#   product       product id or slug, or "none" for items with no product (list)
#   sentiment     complaint, praise, question, neutral (list)
#   category      category id or name (list)
#   status        new, claimed, in_progress, handled, dismissed (list)
#   source        source id (list)
#   source_kind   slack, discord, intercom, email, x (list)
#   range         last message within 24h, 7d, 30d, or 90d
#   since, until  last message at or after / before an ISO 8601 time
#   needs_review  true for items flagged for human review
#   overdue       true for claimed items past the report-back window
#   relevance     relevant (default), not_relevant, or all
#
# Results are ordered most recent message first. Unknown filters and invalid values raise InvalidFilter
# at construction, so callers can report the problem instead of silently widening the feed.
class ItemsQuery
  class InvalidFilter < ArgumentError
    attr_reader :filter

    def initialize(filter, message)
      @filter = filter
      super("#{filter}: #{message}")
    end
  end

  LIST_FILTERS = %i[product sentiment category status source source_kind].freeze
  SCALAR_FILTERS = %i[range since until needs_review overdue relevance].freeze
  FILTERS = (LIST_FILTERS + SCALAR_FILTERS).freeze
  RANGES = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }.freeze
  RELEVANCE = %w[relevant not_relevant all].freeze
  NO_PRODUCT = "none"
  TRUE_VALUES = [ true, "true", "1" ].freeze
  FALSE_VALUES = [ false, "false", "0" ].freeze

  def self.from_params(params)
    new(**params.permit(*SCALAR_FILTERS, *LIST_FILTERS, **LIST_FILTERS.index_with { [] }).to_h.symbolize_keys)
  end

  # The filters that will be applied, normalized: lists are arrays of strings, flags are true, blanks are
  # dropped, and relevance is always present.
  attr_reader :filters

  def initialize(**filters)
    unknown = filters.keys.map(&:to_sym) - FILTERS
    raise InvalidFilter.new(unknown.first, "is not a filter") if unknown.any?

    @filters = normalize(filters.transform_keys(&:to_sym))
  end

  def call
    scope = Item.recent_first
    scope = by_relevance(scope)
    scope = by_product(scope, filters[:product]) if filters[:product]
    scope = by_category(scope, filters[:category]) if filters[:category]
    scope = scope.where(sentiment: filters[:sentiment]) if filters[:sentiment]
    scope = scope.where(status: filters[:status]) if filters[:status]
    scope = scope.where(source_id: filters[:source]) if filters[:source]
    scope = scope.where(source_kind: filters[:source_kind]) if filters[:source_kind]
    scope = scope.where(last_message_at: range_start..) if range_start
    scope = scope.where(last_message_at: ...filters[:until]) if filters[:until]
    scope = scope.where(needs_review: true) if filters[:needs_review]
    scope = scope.where(overdue: true) if filters[:overdue]
    scope
  end

  private

  def normalize(raw)
    normalized = {}
    LIST_FILTERS.each do |name|
      values = Array(raw[name]).map { |value| value.to_s.strip }.compact_blank.uniq
      normalized[name] = validate_list(name, values) if values.any?
    end
    normalized[:range] = validate_range(raw[:range]) if raw[:range].present?
    normalized[:since] = parse_time(:since, raw[:since]) if raw[:since].present?
    normalized[:until] = parse_time(:until, raw[:until]) if raw[:until].present?
    normalized[:needs_review] = true if flag(:needs_review, raw[:needs_review])
    normalized[:overdue] = true if flag(:overdue, raw[:overdue])
    normalized[:relevance] = validate_relevance(raw[:relevance].presence || "relevant")
    normalized
  end

  def validate_list(name, values)
    if (allowed = { sentiment: Item.sentiments, status: Item.statuses, source_kind: Source.kinds }[name]&.values)
      invalid = values - allowed
      raise InvalidFilter.new(name, "#{invalid.first.inspect} is not one of #{allowed.join(', ')}") if invalid.any?
    elsif name == :source && (invalid = values.grep_v(/\A\d+\z/)).any?
      raise InvalidFilter.new(name, "#{invalid.first.inspect} is not a source id")
    end

    values
  end

  def validate_range(value)
    RANGES.key?(value.to_s) ? value.to_s : raise(InvalidFilter.new(:range, "must be one of #{RANGES.keys.join(', ')}"))
  end

  def validate_relevance(value)
    RELEVANCE.include?(value.to_s) ? value.to_s : raise(InvalidFilter.new(:relevance, "must be one of #{RELEVANCE.join(', ')}"))
  end

  def parse_time(name, value)
    value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? value : Time.zone.iso8601(value.to_s)
  rescue ArgumentError
    raise InvalidFilter.new(name, "must be an ISO 8601 time")
  end

  def flag(name, value)
    return false if value.nil? || value == "" || FALSE_VALUES.include?(value)
    return true if TRUE_VALUES.include?(value)

    raise InvalidFilter.new(name, "must be true or false")
  end

  def range_start
    [ filters[:range] && RANGES.fetch(filters[:range]).ago, filters[:since] ].compact.max
  end

  def by_relevance(scope)
    case filters[:relevance]
    when "relevant" then scope.where(relevant: true)
    when "not_relevant" then scope.where(relevant: false)
    else scope
    end
  end

  def by_product(scope, values)
    ids, slugs = values.without(NO_PRODUCT).partition { |value| value.match?(/\A\d+\z/) }
    matching = Item.where(product_id: ids).or(Item.where(product_id: Product.where(slug: slugs).select(:id)))
    matching = matching.or(Item.where(product_id: nil)) if values.include?(NO_PRODUCT)
    scope.and(matching)
  end

  def by_category(scope, values)
    ids, names = values.partition { |value| value.match?(/\A\d+\z/) }
    scope.and(Item.where(category_id: ids).or(Item.where(category_id: Category.where(name: names).select(:id))))
  end
end
