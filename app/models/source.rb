class Source < ApplicationRecord
  enum :kind, { slack: "slack", discord: "discord", intercom: "intercom", email: "email", x: "x" }, validate: true
  enum :status, { active: "active", paused: "paused", paused_for_budget: "paused_for_budget" }, validate: true

  belongs_to :default_product, class_name: "Product", optional: true
  has_many :items, dependent: :restrict_with_error
  has_many :messages, dependent: :restrict_with_error

  normalizes :selector, with: ->(selector) { selector.strip }

  validates :name, :selector, presence: true
  validates :selector, uniqueness: { scope: :kind }
  validates :monthly_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ordered, -> { order(:kind, :name) }

  def self.for(kind, selector)
    find_by(kind: kind, selector: selector.to_s.strip)
  end

  def record_message_received!(at = Time.current)
    update!(last_message_at: [ last_message_at, at ].compact.max, last_error: nil, last_error_at: nil)
  end

  def record_error!(error)
    update!(last_error: error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s,
      last_error_at: Time.current)
  end

  def healthy?
    active? && last_error.blank?
  end
end
