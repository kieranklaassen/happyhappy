# Bad news about one product, grouping every negative anomaly that arrived within the correlation
# window (Setting#incident_window) into one Slack ping and one thing to resolve (Incidents::Correlate,
# Incidents::Resolve).
class Incident < ApplicationRecord
  WEBHOOK_EVENT = "incident.resolved".freeze

  enum :status, { open: "open", resolved: "resolved" }, validate: true

  belongs_to :product
  belongs_to :resolved_by, polymorphic: true, optional: true
  has_many :anomalies, -> { order(:id) }, class_name: "DetectedAnomaly", dependent: :nullify, inverse_of: :incident

  validates :opened_at, :last_anomaly_at, presence: true

  scope :recent_first, -> { order(opened_at: :desc, id: :desc) }

  # The anomaly's incident, or a new one for bad news detected before incidents existed.
  def self.for_anomaly!(anomaly)
    anomaly.incident || transaction do
      create!(product: anomaly.product, opened_at: anomaly.first_seen_at, last_anomaly_at: anomaly.last_seen_at)
        .tap { |incident| anomaly.update!(incident: incident) }
    end
  end

  def url
    "#{ENV.fetch("PUBLIC_BASE_URL", "http://localhost:3000").chomp("/")}/incidents/#{id}"
  end

  def slack_posted?
    slack_channel_id.present? && slack_message_ts.present?
  end

  # Items that drove any of the incident's anomalies, most recent anomaly first.
  def item_ids
    anomalies.reverse.flat_map(&:item_ids).uniq
  end

  def sources
    ids = anomalies.filter_map(&:source_id) + Item.where(id: item_ids).distinct.pluck(:source_id)
    Source.where(id: ids.uniq).order(:name).to_a
  end

  def to_props
    {
      id: id,
      product: { id: product.id, slug: product.slug, name: product.name },
      status: status,
      opened_at: opened_at.iso8601,
      last_anomaly_at: last_anomaly_at.iso8601,
      resolved_at: resolved_at&.iso8601,
      resolved_by: resolved_by_name,
      resolution_note: resolution_note,
      items_handled: items_handled,
      item_ids: item_ids,
      sources: sources.map { |source| { id: source.id, kind: source.kind, name: source.name } },
      slack_posted: slack_posted?,
      url: url,
      anomalies: anomalies.map(&:to_props)
    }
  end
end
