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

  # Agent claims, reports, releases, and the overdue sweep move items with
  # update_all, which skips Item's after_commit ping to open mood dashboards.
  UPDATE_ALL_KINDS = %w[claimed released reassigned reported overdue].freeze

  # The event is already committed; a webhook problem must not fail ingest, classification, or claims.
  after_create_commit do
    Rails.error.handle(context: { item_event_id: id }) { Webhooks::FanOut.call(self) }
  end
  after_create_commit -> { MoodChannel.refresh }, if: -> { kind.in?(UPDATE_ALL_KINDS) }

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
