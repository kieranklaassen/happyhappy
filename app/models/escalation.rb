class Escalation < ApplicationRecord
  belongs_to :item
  belongs_to :product
  belongs_to :message, optional: true

  validates :slack_channel_id, presence: true

  scope :posted, -> { where.not(posted_at: nil) }
  scope :pending, -> { where(posted_at: nil) }

  def posted?
    posted_at.present?
  end
end
