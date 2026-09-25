# One unusual stretch of a product's series (see Anomalies::Detect). The anomaly gem owns the
# top-level Anomaly constant, hence the name.
class DetectedAnomaly < ApplicationRecord
  self.table_name = "anomalies"

  METRICS = %w[volume complaint_share mean_anger mood_share category_volume].freeze
  GRANULARITIES = { "hour" => 1.hour, "day" => 1.day }.freeze
  SEVERITIES = %w[low medium high].freeze
  ITEM_LIMIT = 50
  WEBHOOK_EVENT = "anomaly.detected".freeze

  enum :status, { active: "active", ended: "ended" }, validate: true

  belongs_to :product
  belongs_to :source, optional: true

  validates :metric, inclusion: { in: METRICS }
  validates :granularity, inclusion: { in: GRANULARITIES.keys }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :window_start, :window_end, :first_seen_at, :last_seen_at, presence: true

  scope :recent_first, -> { order(window_end: :desc, id: :desc) }

  def self.for_series(series)
    where(product_id: series.product_id, source_id: series.source_id, granularity: series.granularity)
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
      severity: severity,
      status: status,
      historical: historical,
      item_ids: item_ids,
      first_seen_at: first_seen_at.iso8601,
      last_seen_at: last_seen_at.iso8601,
      ended_at: ended_at&.iso8601
    }
  end
end
