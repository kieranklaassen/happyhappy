module Slack
  # Block Kit payload for one product's digest of one local calendar day (R31):
  # sentiment mix, top categories, standout complaints and praise, and what
  # agents handled. A day with no items says it was quiet (AE8).
  #
  #   Slack::DigestMessage.new(product, Date.yesterday).to_h # => { text:, blocks: }
  class DigestMessage
    include Formatting

    STANDOUT_COUNT = 3
    TOP_CATEGORY_COUNT = 3

    def initialize(product, date)
      @product = product
      @date = date
      @window = date.in_time_zone.all_day
    end

    def to_h
      { text: title, blocks: quiet? ? quiet_blocks : busy_blocks }
    end

    def quiet?
      items.none?
    end

    private

    def title
      "#{@product.name} digest for #{@date.to_fs(:long)}"
    end

    def quiet_blocks
      [
        section("*#{escape(title)}*"),
        section("Quiet day: no new feedback about #{escape(@product.name)}."),
        (context(handled_text) if handled_counts.any?)
      ].compact
    end

    def busy_blocks
      [
        section("*#{escape(title)}*\n#{pluralize(items.count, "item")} with new messages"),
        section("*Sentiment mix*\n#{sentiment_text}"),
        section("*Top categories*\n#{top_categories_text}"),
        section("*Standout complaints*\n#{standouts_text(standout_complaints, :anger_probability, "anger")}"),
        section("*Standout praise*\n#{standouts_text(standout_praise, :sentiment_probability, "praise")}"),
        context(handled_text)
      ]
    end

    # Relevant items of this product with at least one customer message received in the window.
    def items
      @items ||= @product.items.relevant.where(id: Message.from_customers.where(occurred_at: @window).select(:item_id))
    end

    def sentiment_text
      counts = items.group(:sentiment).count
      Item.sentiments.keys.map { |sentiment| "#{sentiment.humanize}: #{counts.fetch(sentiment, 0)}" }.join("  |  ")
    end

    def top_categories_text
      counts = items.where.not(category_id: nil).group(:category_id).count.max_by(TOP_CATEGORY_COUNT, &:last)
      return "None" if counts.empty?

      names = Category.where(id: counts.map(&:first)).pluck(:id, :name).to_h
      counts.map { |id, count| "#{escape(names[id])} (#{count})" }.join(", ")
    end

    def standout_complaints
      items.complaint.where.not(anger_probability: nil).order(anger_probability: :desc).limit(STANDOUT_COUNT)
    end

    def standout_praise
      items.praise.order(sentiment_probability: :desc).limit(STANDOUT_COUNT)
    end

    def standouts_text(scope, probability, label)
      lines = scope.map do |item|
        body = item.messages.from_customers.where(occurred_at: @window).last&.body
        "#{link(item_url(item), customer_handle(item))} (#{label} #{percent(item.public_send(probability))})\n#{quote(body)}"
      end
      lines.presence&.join("\n") || "None"
    end

    def handled_text
      return "Agents handled nothing." if handled_counts.empty?

      names = Agent.where(id: handled_counts.keys).pluck(:id, :name).to_h
      handled = handled_counts.map { |id, count| "#{escape(names[id])} #{count}" }.join(", ")
      "Agents handled #{pluralize(handled_counts.values.sum, "item")}: #{handled}"
    end

    # Distinct items per agent reported handled during the window.
    def handled_counts
      @handled_counts ||= ItemEvent.reported.where(actor_type: "Agent", created_at: @window)
        .where(item_id: @product.items.select(:id))
        .where("json_extract(item_events.data, '$.status') = ?", "handled")
        .group(:actor_id).count("DISTINCT item_events.item_id")
    end

    def pluralize(count, noun)
      "#{count} #{noun.pluralize(count)}"
    end
  end
end
