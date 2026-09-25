class WebhookEndpoint < ApplicationRecord
  EVENTS = %w[item.arrived item.classified item.status_changed item.escalated agent.reported anomaly.detected].freeze

  encrypts :secret

  has_many :deliveries, -> { order(created_at: :desc, id: :desc) }, class_name: "WebhookDelivery",
    dependent: :delete_all, inverse_of: :webhook_endpoint

  normalizes :name, :url, with: ->(value) { value.strip }
  normalizes :events, :sentiments, with: ->(values) { Array(values).map(&:to_s).compact_blank.uniq }
  normalizes :product_ids, :category_ids, with: ->(ids) { Array(ids).compact_blank.map(&:to_i).uniq }

  before_validation :generate_secret, if: -> { secret.blank? }

  validates :name, presence: true
  validates :secret, presence: true
  validates :events, presence: true
  validate :url_must_be_http_or_https
  validate :events_must_be_known
  validate :sentiments_must_be_known

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name, :id) }

  def self.generate_secret
    "whsec_#{SecureRandom.base58(40)}"
  end

  def rotate_secret!
    update!(secret: self.class.generate_secret)
  end

  def subscribed?(event)
    events.include?(event)
  end

  # Empty filters match everything; a set filter must match the item's current label.
  def matches?(item)
    (product_ids.empty? || product_ids.include?(item.product_id)) &&
      (category_ids.empty? || category_ids.include?(item.category_id)) &&
      (sentiments.empty? || sentiments.include?(item.sentiment))
  end

  # Anomalies have a product and sometimes a category, but no sentiment, so sentiment filters do not apply.
  def matches_anomaly?(anomaly)
    (product_ids.empty? || product_ids.include?(anomaly.product_id)) &&
      (category_ids.empty? || (anomaly.category.present? && category_ids.include?(anomaly.category.id)))
  end

  private

  def generate_secret
    self.secret = self.class.generate_secret
  end

  def url_must_be_http_or_https
    uri = URI.parse(url.to_s)
    allowed = Rails.env.development? ? %w[http https] : %w[https]
    return if allowed.include?(uri.scheme) && uri.host.present?

    errors.add(:url, Rails.env.development? ? "must be an http or https URL" : "must be an https URL")
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  end

  def events_must_be_known
    unknown = events - EVENTS
    errors.add(:events, "include unknown events: #{unknown.join(', ')}") if unknown.any?
  end

  def sentiments_must_be_known
    unknown = sentiments - Item.sentiments.keys
    errors.add(:sentiments, "include unknown sentiments: #{unknown.join(', ')}") if unknown.any?
  end
end
