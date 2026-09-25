# Feed search (U25). Truffler stores one row per label per item and ranks a
# query by the labels it names, plus FTS5 keyword hits over the item's text.
#
# Every label but one is supplied (`from:`) from what classification already
# wrote on the item, so it costs nothing and Jev is never asked it twice.
# Watched columns refresh a supplied label after commit. Bump a label's
# `version:` when its `from:` logic changes, then run the free backfill
# (docs/search.md).
#
# The dashboard mood is not a label: it is derived from sentiment and anger,
# and Jev reading "angry" as both the anger label and a mood filtered on two
# answers that contradict each other.
#
# The one asked label, churn_risk, is something classification does not
# answer: a customer about to leave hides as easily in a bug report or a
# billing question as under the cancellation category.
module Item::Searchable
  extend ActiveSupport::Concern

  SENTIMENTS = {
    "complaint" => "Unhappy about something: a problem, a failure, a charge, or a letdown",
    "praise" => "Happy: thanks, compliments, or a success story",
    "question" => "Asking how something works or for something to be done",
    "neutral" => "An observation, announcement, or small talk",
    "relieved" => "Was upset earlier and is satisfied now"
  }.freeze

  STATUSES = {
    "new" => "Nobody has picked it up yet", "claimed" => "An agent has claimed it",
    "in_progress" => "Being worked on", "handled" => "Done", "dismissed" => "Dismissed as needing nothing"
  }.freeze

  CHURN_RISK = {
    true => "Says they will cancel, stop paying, ask for a refund and leave, or switch to another tool, " \
      "even inside a bug report or a billing question",
    false => "Frustrated or asking for help, but nothing suggests they are about to leave"
  }.freeze

  CONVERSATION_CHARS = 4_000

  included do
    include Truffler::Model

    after_commit :refresh_search_document, if: -> { destroyed? || saved_changes.keys.intersect?(%w[author_handle author_name author_email]) }

    truffler do
      reads :search_author, :search_conversation

      label :sentiment, :choice, options: Item::Searchable.named_options(SENTIMENTS), description: "how the customer feels",
        from: ->(item) { item.sentiment }, watch: %i[sentiment], filter_at: 0.5
      label :product, :choice, options: ->(_) { Item::Searchable.product_options }, description: "which Every product it is about",
        from: ->(item) { item.product&.slug || (NO_PRODUCT if item.classified?) }, watch: %i[product_id relevance_probability],
        filter_at: 0.5
      label :category, :choice, options: ->(_) { Item::Searchable.category_options }, description: "what the feedback is about",
        from: ->(item) { item.category&.name || (OTHER_CATEGORY if item.classified?) }, watch: %i[category_id relevance_probability],
        filter_at: 0.5
      label :anger, :noul, description: "the customer is angry",
        from: ->(item) { item.anger_probability }, watch: %i[anger_probability], filter_at: 0.5, boost: 2.0
      label :needs_action, :noul, description: "someone at Every needs to act or reply",
        from: ->(item) { item.actionability }, watch: %i[actionability], filter_at: Actionability::SHOULD_REPLY, boost: 2.0
      label :status, :choice, options: Item::Searchable.named_options(STATUSES), description: "where the team is with it",
        from: ->(item) { item.status }, watch: %i[status], filter_at: 0.5
      label :source, :choice, options: Source.kinds.values, description: "the channel it came from (Slack, Discord, Intercom, email, X)",
        from: ->(item) { item.source_kind }, filter_at: 0.5
      label :team_replied, :noul, description: "someone at Every already replied in the thread",
        from: ->(item) { item.messages.author_team.exists? }, filter_at: 0.5
      label :needs_review, :noul, description: "a label is low confidence and needs a human to check it",
        from: ->(item) { item.needs_review }, watch: %i[needs_review], filter_at: 0.5

      label :churn_risk, :noul, question: "Is this customer at risk of leaving?", criteria: CHURN_RISK,
        description: "the customer might cancel or leave", watch: %i[last_message_at], filter_at: 0.6, boost: 2.0

      keyword ->(scope, tokens) { FeedSearch::TextIndex.matching(scope, tokens) }
      order :last_message_at, :desc
      arrived_at :last_message_at
      surface :feed, explicit_action: :enter
    end
  end

  NO_PRODUCT = Classification::SchemaBuilder::NO_PRODUCT
  OTHER_CATEGORY = Classification::SchemaBuilder::OTHER_CATEGORY

  # Retired products and categories stay, so their past items stay findable.
  # `none` and `other` are answers `from:` gives, and the option keys are part
  # of every stored product and category label's fingerprint. Jev reads the
  # description; query words match only the short `search:` text (SearchBlurb).
  def self.product_options
    options = Product.ordered.to_h do |product|
      description = [ product.name, product.description.presence, product.hint_words.presence&.join(", ") ].compact.join(": ")
      [ product.slug, { description: description, search: product.search_blurb.presence || product.name } ]
    end
    options[NO_PRODUCT] ||= { description: "Not about any Every product", search: "no product" }
    options
  end

  def self.category_options
    options = Category.ordered.to_h do |category|
      [ category.name, { description: category.description.presence, search: category.search_blurb.presence || category.name } ]
    end
    options[OTHER_CATEGORY] ||= { description: "Fits no other category", search: OTHER_CATEGORY }
    options
  end

  # A fixed option's search text is its own name, so the long description
  # ("a problem, a failure, a charge") never claims a query word.
  def self.named_options(descriptions)
    descriptions.to_h { |option, description| [ option, { description: description, search: option.humanize(capitalize: false) } ] }
  end

  # Relevance is the first answer classification writes, so an item without
  # one has not been classified yet.
  def classified?
    !relevance_probability.nil?
  end

  def search_author
    [ author_handle, author_name, author_email ].compact_blank.join(" ")
  end

  # Newest first: truffler cuts long fields from the end, so the oldest
  # messages are the ones that fall off.
  def search_conversation
    messages.reorder(occurred_at: :desc, id: :desc).limit(20).map do |message|
      "#{message.author_team? ? 'Every team' : 'Customer'}: #{message.body}"
    end.join("\n\n").first(CONVERSATION_CHARS)
  end

  private

  def refresh_search_document
    FeedSearch::TextIndex.refresh(id)
  end
end
