module Classification
  # Stores one message's answers and rolls every classified message of its item
  # up to the item's labels (KTD2):
  #
  # - relevant when any open message is relevant (relevance at least 0.5)
  # - product, category, and sentiment from the latest relevant open message,
  #   falling back to the latest message while none are relevant
  # - anger is the highest among the relevant open messages
  # - needs review when a relevant item has a machine label below the
  #   low-confidence threshold
  #
  # Open messages are those received since the item's last status change. Labels
  # a human set are never overwritten. Writes a classified event and publishes
  # item.classified after commit.
  class Apply
    RELEVANCE_THRESHOLD = 0.5

    def self.call(...)
      new(...).call
    end

    def initialize(message:, answers:)
      @message = message
      @answers = answers
    end

    def call
      item = @message.item
      item.with_lock do
        @message.update!(
          classification_answers: @answers,
          anger_probability: noul(@answers, "anger"),
          classified_at: Time.current,
          classification_error: nil
        )
        roll_up(item)
        item.save!
        item.record_event!(:classified, message_id: @message.id, **summary(item))
      end
      item.publish_classified(@message)
      item
    end

    private

    def roll_up(item)
      classified = item.messages.classified.to_a
      open = classified.select { |message| message.created_at >= item.status_changed_at }
      # A message classified after a status change (a late job) has no open
      # siblings; judge the thread by everything classified so far.
      open = classified if open.empty?
      relevant = open.select { |message| relevant?(message) }
      labels = (relevant.last || classified.last).classification_answers

      item.relevance_probability = open.map { |message| noul(message.classification_answers, "relevant") }.max
      item.relevant = relevant.any? unless item.relevant_human_set?
      item.anger_probability = relevant.map(&:anger_probability).compact.max

      assign_product(item, labels["product"]) unless item.product_human_set?
      assign_category(item, labels["category"]) unless item.category_human_set?
      assign_sentiment(item, labels["sentiment"]) unless item.sentiment_human_set?

      item.needs_review = item.relevant? && low_confidence?(item)
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

    def assign_sentiment(item, answer)
      item.sentiment = answer["choice"].presence_in(Item.sentiments.keys)
      item.sentiment_probability = probability(answer, answer["choice"])
    end

    def low_confidence?(item)
      threshold = Setting.current.low_confidence_threshold
      %w[product category sentiment].any? do |label|
        next false if item.public_send(:"#{label}_human_set?")

        probability = item.public_send(:"#{label}_probability")
        probability.nil? || probability < threshold
      end
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
        needs_review: item.needs_review
      }
    end
  end
end
