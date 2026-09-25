# One unusual stretch of a product's series (see Anomalies::Detect). The anomaly gem owns the
# top-level Anomaly constant, hence the name.
class DetectedAnomaly < ApplicationRecord
  self.table_name = "anomalies"

  METRICS = %w[volume complaint_share mean_anger mood_share category_volume].freeze
  GRANULARITIES = { "hour" => 1.hour, "day" => 1.day }.freeze
  SEVERITIES = %w[low medium high].freeze
  HIGHLIGHTS = %w[notable big huge].freeze
  ITEM_LIMIT = 50
  WEBHOOK_EVENT = "anomaly.detected".freeze

  enum :status, { active: "active", ended: "ended" }, validate: true

  belongs_to :product
  belongs_to :source, optional: true

  validates :metric, inclusion: { in: METRICS }
  validates :granularity, inclusion: { in: GRANULARITIES.keys }
  validates :polarity, inclusion: { in: Anomalies::Polarity::ALL }
  validates :severity, inclusion: { in: SEVERITIES }, if: :negative?
  validates :severity, absence: true, unless: :negative?
  validates :highlight, inclusion: { in: HIGHLIGHTS }, if: :positive?
  validates :highlight, absence: true, unless: :positive?
  validates :window_start, :window_end, :first_seen_at, :last_seen_at, presence: true

  scope :recent_first, -> { order(window_end: :desc, id: :desc) }

  # Severity is for bad news only; good news gets a highlight at the same strength, neutral neither.
  #
  #   DetectedAnomaly.grade(metric: "mood_share", dimension: "beaming", item_ids: [], level: 1)
  #   # => { polarity: "positive", severity: nil, highlight: "big" }
  def self.grade(metric:, dimension:, item_ids:, level:)
    polarity = Anomalies::Polarity.for(metric: metric, dimension: dimension, item_ids: item_ids)
    {
      polarity: polarity,
      severity: (SEVERITIES.fetch(level) if polarity == "negative"),
      highlight: (HIGHLIGHTS.fetch(level) if polarity == "positive")
    }
  end

  # Bad news bad enough to interrupt the Slack channel. Only the all-sources row
  # alerts, since each per-source row repeats the same spike.
  def slack_alertable?
    active? && !historical? && negative? && severity == "high" && source_id.nil?
  end

  def positive?
    polarity == "positive"
  end

  def negative?
    polarity == "negative"
  end

  # 0 to 2, from severity or highlight; neutral anomalies have no strength of their own.
  def strength
    SEVERITIES.index(severity) || HIGHLIGHTS.index(highlight) || 0
  end

  def category
    Category.find_by(id: dimension) if metric == "category_volume"
  end

  def label
    case metric
    when "volume" then "Message volume"
    when "complaint_share" then "Complaint share"
    when "mean_anger" then "Mean anger"
    when "mood_share" then "#{dimension.to_s.humanize} customers"
    when "category_volume" then "#{category&.name&.upcase_first || "Category"} messages"
    end
  end

  def share?
    metric.in?(%w[complaint_share mean_anger mood_share])
  end

  def end!(at: Time.current)
    update!(status: :ended, ended_at: at) if active?
  end

  def to_props
    {
      id: id,
      product: { id: product.id, slug: product.slug, name: product.name },
      source: source && { id: source.id, kind: source.kind, name: source.name },
      metric: metric,
      dimension: dimension,
      label: label,
      granularity: granularity,
      window_start: window_start.iso8601,
      window_end: window_end.iso8601,
      expected: expected.round(3),
      actual: actual.round(3),
      share: share?,
      z_score: z_score.round(2),
      polarity: polarity,
      severity: severity,
      highlight: highlight,
      status: status,
      historical: historical,
      item_ids: item_ids,
      first_seen_at: first_seen_at.iso8601,
      last_seen_at: last_seen_at.iso8601,
      ended_at: ended_at&.iso8601
    }
  end
end
