class Source < ApplicationRecord
  enum :kind, { slack: "slack", discord: "discord", intercom: "intercom", email: "email", x: "x", custom: "custom" },
    validate: true
  enum :status, { active: "active", paused: "paused", paused_for_budget: "paused_for_budget" }, validate: true

  belongs_to :default_product, class_name: "Product", optional: true
  has_many :items, dependent: :restrict_with_error
  has_many :messages, dependent: :restrict_with_error

  encrypts :signing_secret

  normalizes :selector, with: ->(selector) { selector.strip }

  before_validation :assign_custom_webhook_credentials, if: :custom?

  validates :name, :selector, presence: true
  validates :selector, uniqueness: { scope: :kind }
  validates :monthly_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :custom_source_has_product, if: :custom?

  scope :ordered, -> { order(:kind, :name) }

  def self.for(kind, selector)
    find_by(kind: kind, selector: selector.to_s.strip)
  end

  def self.generate_signing_secret
    "hhsec_#{SecureRandom.base58(40)}"
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

  def rotate_signing_secret!
    update!(signing_secret: self.class.generate_signing_secret)
  end

  private

  # A custom source is addressed by its public token, so the token doubles as
  # its selector.
  def assign_custom_webhook_credentials
    self.public_token ||= SecureRandom.base58(24)
    self.signing_secret ||= self.class.generate_signing_secret
    self.selector = public_token
  end

  def custom_source_has_product
    errors.add(:default_product_id, :blank) if default_product.nil?
  end
end
