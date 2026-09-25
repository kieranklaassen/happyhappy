class Message < ApplicationRecord
  belongs_to :item
  belongs_to :source

  # Who wrote it: a customer or Every's own team. Unknown until the provider's
  # metadata or, failing that, the classifier decides (Messages::AuthorRole).
  enum :author_role, { customer: "customer", team: "team", unknown: "unknown" }, prefix: :author, validate: true

  validates :external_id, presence: true, uniqueness: { scope: :source_id }
  validates :occurred_at, presence: true
  validates :anger_probability,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :classified, -> { where.not(classified_at: nil) }
  scope :unclassified, -> { where(classified_at: nil) }
  # Customer voices, including authors nobody could place yet.
  scope :from_customers, -> { where.not(author_role: "team") }

  def classified?
    classified_at.present?
  end

  # The author's display name as the provider sent it with this message, which
  # can differ from the item's author on a shared thread.
  def author_label
    payload = raw_payload.is_a?(Hash) ? raw_payload : {}
    author = payload["author"].is_a?(Hash) ? payload["author"] : {}
    author["global_name"].presence || author["username"].presence || author["name"].presence ||
      payload.dig("part", "author", "name").presence || payload.dig("FromFull", "Name").presence ||
      item&.author_name.presence || item&.author_handle
  end
end
