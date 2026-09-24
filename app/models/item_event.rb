class ItemEvent < ApplicationRecord
  enum :kind, {
    arrived: "arrived",
    classified: "classified",
    classification_failed: "classification_failed",
    corrected: "corrected",
    claimed: "claimed",
    released: "released",
    reassigned: "reassigned",
    reported: "reported",
    status_changed: "status_changed",
    overdue: "overdue",
    escalated: "escalated"
  }, validate: true

  belongs_to :item
  belongs_to :actor, polymorphic: true, optional: true

  validates :actor_type, inclusion: { in: %w[User Agent] }, allow_nil: true

  def readonly?
    persisted? || super
  end

  def actor_label
    case actor
    when User then actor.name.presence || actor.email_address
    when Agent then actor.name
    else "happyhappy"
    end
  end
end
