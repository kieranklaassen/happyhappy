module Slack
  # Block Kit payload for the one daily overview of every product, posted to the
  # Settings Slack channel: who wrote in, how they feel per product, who needs
  # someone at Every (actionability), unusual activity worded by polarity, and
  # standout praise. A day with no items says it was quiet.
  #
  #   Slack::OverviewMessage.new(Date.new(2026, 9, 24), time_zone: "America/Los_Angeles").to_h # => { text:, blocks: }
  class OverviewMessage
    include Formatting
    include AnomalyWording

    ATTENTION_COUNT = 5
    PRAISE_COUNT = 3
    ANOMALY_COUNT = 8
    POLARITY_ORDER = { "negative" => 0, "positive" => 1, "neutral" => 2 }.freeze

    def initialize(date, time_zone:)
      @date = date
      @window = date.in_time_zone(time_zone).all_day
    end

    def to_h
      { text: title, blocks: items.none? ? quiet_blocks : busy_blocks }
    end

    private

    def title
      "happyhappy daily overview for #{@date.to_fs(:long)}"
    end

    def quiet_blocks
      [
        section("*#{escape(title)}*\nQuiet day: no new customer feedback."),
        (section("*Unusual activity*\n#{anomalies_text}") if anomalies.any?)
      ].compact
    end

    def busy_blocks
      [
        section("*#{escape(title)}*\n#{pluralize(items.count, "item")} with new customer messages\n#{sentiment_text}"),
        section("*By product*\n#{products_text}"),
        section("*Needs attention*\n#{attention_text}"),
        section("*Unusual activity*\n#{anomalies_text}"),
        section("*Standout praise*\n#{praise_text}"),
        context(handled_text)
      ]
    end

    # Relevant items with at least one customer message received in the window.
    def items
      @items ||= Item.relevant.where(id: Message.from_customers.where(occurred_at: @window).select(:item_id))
    end

    def sentiment_text
      counts = items.group(:sentiment).count
      Item.sentiments.keys.map { |sentiment| "#{sentiment.humanize}: #{counts.fetch(sentiment, 0)}" }.join("  |  ")
    end

    def products_text
      totals = items.group(:product_id).count
      complaints = items.complaint.group(:product_id).count
      praise = items.praise.group(:product_id).count
      act_now = items.where(actionability_band: "act_now").group(:product_id).count
      names = Product.where(id: totals.keys.compact).pluck(:id, :name).to_h

      lines = totals.sort_by { |id, count| [ -count, names[id].to_s ] }.map do |id, count|
        parts = [ pluralize(count, "item") ]
        parts << pluralize(complaints[id], "complaint") if complaints[id]
        parts << "#{praise[id]} praise" if praise[id]
        parts << "#{act_now[id]} act now" if act_now[id]
        "*#{escape(names[id] || "No product")}*: #{parts.join(" · ")}"
      end
      quiet = Product.active.where.not(id: totals.keys.compact).order(:name).pluck(:name)
      lines << "Quiet: #{quiet.map { |name| escape(name) }.join(", ")}" if quiet.any?
      lines.join("\n")
    end

    # The customers who most need someone at Every, act-now first.
    def attention_text
      scope = items.where(actionability_band: Actionability::ACTIONABLE_BANDS)
        .order(Arel.sql("CASE actionability_band WHEN 'act_now' THEN 0 ELSE 1 END"))
        .merge(Item.by_actionability).includes(:product).limit(ATTENTION_COUNT)
      lines = scope.map do |item|
        band = item.actionability_band == "act_now" ? "act now" : "should reply"
        "#{link(item_url(item), customer_handle(item))} · #{escape(item.product&.name || "No product")} " \
          "(#{band}, #{percent(item.actionability)})\n#{quote(latest_body(item))}"
      end
      lines.presence&.join("\n") || "Nothing waiting on us."
    end

    # Live spikes that touch the day, across all sources (the per-source rows
    # repeat them), bad news first. Windows are half-open, so one ending at the
    # day's start belongs to the day before.
    def anomalies
      @anomalies ||= DetectedAnomaly.where(historical: false, source_id: nil)
        .where(window_start: ...@window.end)
        .where("anomalies.window_end > ?", @window.begin)
        .includes(:product, :source).to_a
        .sort_by { |anomaly| [ POLARITY_ORDER.fetch(anomaly.polarity, 3), -anomaly.strength, -anomaly.z_score ] }
        .first(ANOMALY_COUNT)
    end

    def anomalies_text
      anomalies.map { |anomaly| anomaly_line(anomaly) }.presence&.join("\n") || "Nothing unusual."
    end

    def praise_text
      lines = items.praise.order(sentiment_probability: :desc).includes(:product).limit(PRAISE_COUNT).map do |item|
        "#{link(item_url(item), customer_handle(item))} · #{escape(item.product&.name || "No product")}\n#{quote(latest_body(item))}"
      end
      lines.presence&.join("\n") || "None"
    end

    def latest_body(item)
      item.messages.from_customers.where(occurred_at: @window).last&.body
    end

    def handled_text
      count = ItemEvent.reported.where(actor_type: "Agent", created_at: @window)
        .where("json_extract(item_events.data, '$.status') = ?", "handled")
        .distinct.count(:item_id)
      count.zero? ? "Agents handled nothing." : "Agents handled #{pluralize(count, "item")}."
    end

    def pluralize(count, noun)
      "#{count} #{noun.pluralize(count)}"
    end
  end
end
