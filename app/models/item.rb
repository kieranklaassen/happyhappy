class Item < ApplicationRecord
  CLASSIFIED_EVENT = "item.classified"
  HELD_STATUSES = %w[claimed in_progress].freeze

  enum :status, {
    new: "new", claimed: "claimed", in_progress: "in_progress", handled: "handled", dismissed: "dismissed"
  }, prefix: true, validate: true
  enum :sentiment, {
    complaint: "complaint", praise: "praise", question: "question", neutral: "neutral", relieved: "relieved"
  },
    validate: { allow_nil: true }

  belongs_to :source
  belongs_to :product, optional: true
  belongs_to :category, optional: true
  belongs_to :claimed_by_agent, class_name: "Agent", optional: true, inverse_of: :claimed_items
  has_many :escalations, dependent: :destroy
  has_many :messages, -> { order(:occurred_at, :id) }, dependent: :destroy, inverse_of: :item
  has_many :events, -> { order(:created_at, :id) }, class_name: "ItemEvent", dependent: :delete_all, inverse_of: :item

  include Searchable

  before_validation :copy_source_kind, if: -> { source && source_kind.blank? }
  before_validation -> { self.status_changed_at ||= Time.current }
  # Noise means not relevant, so the band follows every change of relevance,
  # including a person's correction.
  before_save -> { self.actionability_band = Actionability.band(score: actionability, relevant: relevant) },
    if: :relevant_changed?
  after_commit -> { MoodChannel.refresh }

  validates :thread_key, presence: true, uniqueness: { scope: :source_kind }
  validates :source_kind, inclusion: { in: Source.kinds.values }
  validates :last_message_at, presence: true
  validates :product_probability, :category_probability, :sentiment_probability,
    :relevance_probability, :anger_probability, :actionability,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  validates :actionability_band, inclusion: { in: Actionability::BANDS }, allow_nil: true

  scope :relevant, -> { where(relevant: true) }
  scope :by_actionability, -> { order(Arel.sql("actionability IS NULL"), actionability: :desc, last_message_at: :desc, id: :desc) }
  scope :recent_first, -> { order(last_message_at: :desc, id: :desc) }
  scope :unresolved, -> { where(status: %w[new claimed in_progress]) }
  scope :unclaimed, -> { where(claimed_by_agent_id: nil) }

  # Messages received since the last status change; item anger is the highest among them.
  def open_messages
    messages.where(created_at: status_changed_at..)
  end

  def mood
    Mood.for(sentiment: sentiment, anger: anger_probability, sentiment_probability: sentiment_probability,
      furious_at: product&.effective_escalation_threshold || Setting.current.escalation_threshold)
  end

  def record_event!(kind, actor: nil, **data)
    events.create!(kind: kind, actor: actor, data: data)
  end

  def change_status!(new_status, actor: nil, at: Time.current, **data)
    new_status = new_status.to_s
    return false if status == new_status

    transaction do
      from = status
      update!(status: new_status, status_changed_at: at)
      record_event!(:status_changed, actor: actor, from: from, to: new_status, **data)
    end
    true
  end

  def publish_classified(message = nil)
    ActiveSupport::Notifications.instrument(CLASSIFIED_EVENT, item_id: id, message_id: message&.id)
  end

  private

  def copy_source_kind
    self.source_kind = source.kind
  end
end
