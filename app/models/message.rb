class Message < ApplicationRecord
  belongs_to :item, touch: true
  belongs_to :source

  validates :external_id, presence: true, uniqueness: { scope: :source_id }
  validates :occurred_at, presence: true
  validates :anger_probability,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :classified, -> { where.not(classified_at: nil) }
  scope :unclassified, -> { where(classified_at: nil) }

  def classified?
    classified_at.present?
  end
end
