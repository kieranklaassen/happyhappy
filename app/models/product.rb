class Product < ApplicationRecord
  include Retirable

  has_many :items, dependent: :restrict_with_error
  has_many :default_sources, class_name: "Source", foreign_key: :default_product_id,
    inverse_of: :default_product, dependent: :nullify
  has_many :escalations, dependent: :restrict_with_error
  has_many :daily_digests, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.strip }
  normalizes :slug, with: ->(slug) { slug.strip.parameterize }
  normalizes :hint_words, with: ->(words) { Array(words).map { |word| word.to_s.strip }.compact_blank.uniq }
  normalizes :slack_channel_id, with: ->(channel_id) { channel_id.strip.presence }

  before_validation :derive_slug, if: -> { slug.blank? && name.present? }

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :digest_hour, numericality: { only_integer: true, in: 0..23 }
  validates :escalation_threshold,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :ordered, -> { order(:name) }

  def effective_escalation_threshold
    escalation_threshold || Setting.current.escalation_threshold
  end

  private

  def derive_slug
    self.slug = name.parameterize
  end
end
