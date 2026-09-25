class Category < ApplicationRecord
  include Retirable
  include SearchBlurb

  has_many :items, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :name) }
end
