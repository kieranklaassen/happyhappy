# Named DailyDigest because Ruby's stdlib already defines a top-level Digest module.
class DailyDigest < ApplicationRecord
  self.table_name = "digests"

  belongs_to :product

  validates :date, presence: true, uniqueness: { scope: :product_id }

  scope :posted, -> { where.not(posted_at: nil) }

  def posted?
    posted_at.present?
  end
end
