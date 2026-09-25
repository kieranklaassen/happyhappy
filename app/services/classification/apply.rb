module Classification
  # Stores one message's answers and rolls the item's classified customer
  # messages up to the item's labels (KTD2). The item reflects the customer's
  # current state, so its labels come from one message: the latest relevant open
  # customer message (the current message), falling back to the latest customer
  # message while none are relevant.
  #
  # - relevant when any open customer message is relevant (relevance at least 0.5)
  # - product, category, sentiment, and anger from the current message; earlier
  #   messages only inform how the classifier read it
  # - needs review when a relevant item has a machine label below the
  #   low-confidence threshold
  #
  # Team messages never set labels, and an item with no customer message is not
  # relevant. A message whose author was unknown takes the classifier's
  # team_author answer. Open messages are those received since the item's last
  # status change. A claimed or in-progress item with no relevant open message
  # keeps its labels, relevance, and anger, so an off-topic reply cannot drop it
  # from the feed while an agent holds it. Labels a human set are never
  # overwritten. Each classified event records the item's mood, so the timeline
  # shows how it changed.
  #
  # Publishes item.classified after commit, except when quiet: a rerun over
  # stored history records its events as backfill so they neither escalate nor
  # fan out to webhooks.
  class Apply
    RELEVANCE_THRESHOLD = 0.5
    TEAM_AUTHOR_THRESHOLD = 0.5
    ACKNOWLEDGEMENT_LENGTH = 40

    def self.call(...)
      new(...).call
    end

    def initialize(message:, answers:, quiet: false)
      @message = message
      @answers = answers
      @quiet = quiet
    end

    def call
      item = @message.item
      item.with_lock do
        @message.update!(
          classification_answers: @answers,
          anger_probability: noul(@answers, "anger"),
          author_role: resolved_author_role,
          classifier_version: Classification::VERSION,
          classified_at: Time.current,
          classification_error: nil
        )
        roll_up(item)
        item.save!
        item.record_event!(:classified, message_id: @message.id, **summary(item))
      end
      item.publish_classified(@message) unless @quiet
      item
    end

    private

    def resolved_author_role
      answer = noul(@answers, "team_author")
      return @message.author_role unless @message.author_unknown? && answer

      answer >= TEAM_AUTHOR_THRESHOLD ? "team" : "customer"
    end

    def roll_up(item)
      classified = item.messages.classified.reject(&:author_team?)
      return clear(item) if classified.empty?

      # Imported history is created now but written long ago, so it would count as
      # open; it only speaks for an item no live message has reached.
      live = classified.reject(&:backfilled?)
      classified = live if live.any?
      open = classified.select { |message| message.created_at >= item.status_changed_at }
      # A message classified after a status change (a late job) has no open
      # siblings; judge the thread by everything classified so far.
      open = classified if open.empty?
      relevant = open.select { |message| relevant?(message) }
      return if relevant.empty? && held_relevant?(item)

      current = relevant.last || classified.last
      labels = current.classification_answers
      stance = stance_for(current, relevant.presence || classified)

      item.relevance_probability = open.map { |message| noul(message.classification_answers, "relevant") }.max
      item.relevant = relevant.any? unless item.relevant_human_set?
      item.anger_probability = stance.anger_probability

      assign_product(item, labels["product"]) unless item.product_human_set?
      assign_category(item, labels["category"]) unless item.category_human_set?
      assign_sentiment(item, stance.classification_answers["sentiment"]) unless item.sentiment_human_set?

      item.needs_review = item.relevant? && low_confidence?(item)
    end

    # A bare acknowledgement ("ok", "thanks") read as neutral says nothing new
    # about how the customer feels, so the mood stays with the customer's last
    # substantive message.
    def stance_for(current, candidates)
      return current unless acknowledgement?(current)

      candidates.take_while { |message| message != current }.reverse.find { |message| !acknowledgement?(message) } || current
    end

    def acknowledgement?(message)
      message.body.to_s.squish.length <= ACKNOWLEDGEMENT_LENGTH && !message.body.include?("?") &&
        message.classification_answers.dig("sentiment", "choice") == "neutral"
    end

    # Only Every's team has spoken: nothing for the feed or the mood dashboard.
    def clear(item)
      return if held_relevant?(item)

      item.relevant = false unless item.relevant_human_set?
      item.relevance_probability = nil
      item.anger_probability = nil
      item.needs_review = false
    end

    def assign_product(item, answer)
      default = item.source.default_product
      product = Product.active.find_by(slug: answer["choice"]) || (default unless default&.retired?)
      item.product = product
      item.product_probability = probability(answer, product&.slug || answer["choice"])
    end

    def assign_category(item, answer)
      item.category = Category.active.find_by(name: answer["choice"])
      item.category_probability = probability(answer, answer["choice"])
    end

    def assign_sentiment(item, answer, earlier)
      choice = answer["choice"].presence_in(Item.sentiments.keys)
      # Relief needs an earlier upset in the thread; without one it is praise.
      if choice == "relieved" && earlier.none? { |message| upset?(message) }
        item.sentiment = "praise"
        item.sentiment_probability = [ probability(answer, "praise"), probability(answer, "relieved") ].compact.sum
      else
        item.sentiment = choice
        item.sentiment_probability = probability(answer, answer["choice"])
      end
    end

    def upset?(message)
      message.classification_answers.dig("sentiment", "choice") == "complaint" ||
        message.anger_probability.to_f >= Mood::GRUMPY_ANGER
    end

    def low_confidence?(item)
      threshold = Setting.current.low_confidence_threshold
      %w[product category sentiment].any? do |label|
        next false if item.public_send(:"#{label}_human_set?")

        probability = item.public_send(:"#{label}_probability")
        probability.nil? || probability < threshold
      end
    end

    def held_relevant?(item)
      item.status.in?(Item::HELD_STATUSES) && item.relevant?
    end

    def relevant?(message)
      noul(message.classification_answers, "relevant").to_f >= RELEVANCE_THRESHOLD
    end

    def noul(answers, id)
      answers&.dig(id, "noul")&.to_f
    end

    def probability(answer, option)
      answer.dig("probabilities", option)&.to_f || answer["confidence"]&.to_f
    end

    def summary(item)
      {
        relevant: item.relevant,
        product_id: item.product_id,
        category_id: item.category_id,
        sentiment: item.sentiment,
        anger_probability: item.anger_probability,
        mood: item.mood,
        author_role: @message.author_role,
        needs_review: item.needs_review,
        **(@message.backfilled? || @quiet ? { backfill: true } : {}),
        **(@quiet ? { reclassified: true } : {})
      }
    end
  end
end
