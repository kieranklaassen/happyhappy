module Anomalies
  # Buckets customer messages on relevant items into consecutive windows, per product and per product
  # plus source, and turns each bucket into one point per metric:
  #
  #   volume           messages in the window
  #   complaint_share  complaints among messages with a sentiment
  #   mean_anger       mean anger among classified messages
  #   mood_share       share of customers (latest message each) in one mood, one line per mood
  #   category_volume  messages in one category, one line per category
  #
  # Count metrics have a point for every window; ratio metrics carry the denominator in `count` and a
  # nil value when it is zero. `first_index` is the first window with any message for the product and
  # source, so windows before a source existed are never treated as a quiet baseline.
  #
  #   Anomalies::Series.new(windows: [[start, end], ...], granularity: "hour").lines
  class Series
    Line = Data.define(:product_id, :source_id, :granularity, :metric, :dimension, :points, :first_index) do
      def count_metric?
        metric.in?(COUNT_METRICS)
      end
    end
    Point = Data.define(:window_start, :window_end, :value, :count, :item_ids)

    COUNT_METRICS = %w[volume category_volume].freeze
    CUSTOMER_ROLE = "customer".freeze

    Bucket = Struct.new(:messages, :items, :complaints, :sentiments, :complaint_items, :angers, :angry_items,
      :categories, :customers) do
      def self.blank
        new(0, [], 0, 0, [], [], [], Hash.new { |hash, key| hash[key] = [] }, {})
      end
    end

    def initialize(windows:, granularity:)
      @windows = windows
      @granularity = granularity
      @ends = windows.map(&:last)
    end

    def lines
      buckets = bucket_messages
      buckets.flat_map do |(product_id, source_id), by_window|
        first_index = by_window.keys.min
        metric_lines(product_id, source_id, by_window, first_index)
      end
    end

    private

    COLUMNS = [
      "messages.occurred_at", "messages.source_id", "messages.item_id", "messages.anger_probability",
      "messages.classified_at", "items.product_id", "items.category_id", "items.sentiment",
      "items.sentiment_probability", "items.author_email", "items.author_handle", "items.author_name",
      "items.source_kind", "products.escalation_threshold",
      Arel.sql("json_extract(messages.classification_answers, '$.sentiment.choice')"),
      Arel.sql("json_extract(messages.classification_answers, '$.sentiment.confidence')")
    ].freeze

    def messages
      scope = Message.joins(item: :product).merge(Item.relevant)
        .where(occurred_at: @windows.first.first...@windows.last.last)
      # The customer-only filter applies once messages record who wrote them.
      if Message.column_names.include?("author_role")
        scope = scope.where(author_role: [ CUSTOMER_ROLE, nil ])
      end
      scope.order(:occurred_at, :id).pluck(*COLUMNS)
    end

    def bucket_messages
      buckets = Hash.new { |hash, key| hash[key] = Hash.new { |inner, index| inner[index] = Bucket.blank } }
      furious_default = Setting.current.escalation_threshold
      sentiments = Item.sentiments.keys

      messages.each do |occurred_at, source_id, item_id, anger, classified_at, product_id, category_id,
                        item_sentiment, item_confidence, email, handle, name, source_kind, threshold,
                        answer_sentiment, answer_confidence|
        index = @ends.bsearch_index { |window_end| window_end > occurred_at }
        next unless index

        sentiment = answer_sentiment.presence_in(sentiments) || item_sentiment
        confidence = answer_sentiment.presence_in(sentiments) ? answer_confidence : item_confidence
        mood = (Mood.for(sentiment: sentiment, anger: anger, sentiment_probability: confidence,
          furious_at: threshold || furious_default) if classified_at)
        customer = customer_key(item_id, email, handle, name, source_kind)

        [ [ product_id, nil ], [ product_id, source_id ] ].each do |key|
          add(buckets[key][index], item_id:, anger:, classified_at:, category_id:, sentiment:, mood:, customer:)
        end
      end
      buckets
    end

    def add(bucket, item_id:, anger:, classified_at:, category_id:, sentiment:, mood:, customer:)
      bucket.messages += 1
      bucket.items << item_id
      bucket.categories[category_id] << item_id if category_id
      if classified_at && sentiment
        bucket.sentiments += 1
        if sentiment == "complaint"
          bucket.complaints += 1
          bucket.complaint_items << item_id
        end
      end
      if classified_at && anger
        bucket.angers << anger
        bucket.angry_items << [ anger, item_id ] if anger >= Mood::GRUMPY_ANGER
      end
      # Messages arrive oldest first, so the last write is each customer's latest mood.
      bucket.customers[customer] = [ mood, item_id ] if mood && mood != Mood::PENDING
    end

    def metric_lines(product_id, source_id, by_window, first_index)
      line = ->(metric, dimension = nil, &point) do
        points = @windows.each_with_index.map do |(window_start, window_end), index|
          value, count, item_ids = point.call(by_window.fetch(index) { Bucket.blank })
          Point.new(window_start:, window_end:, value:, count:, item_ids: item_ids.uniq)
        end
        Line.new(product_id:, source_id:, granularity: @granularity, metric:, dimension:, points:, first_index:)
      end

      moods = (Mood::ALL + by_window.values.flat_map { |bucket| bucket.customers.values.map(&:first) }).uniq
      categories = by_window.values.flat_map { |bucket| bucket.categories.keys }.uniq.sort

      [
        line.("volume") { |bucket| [ bucket.messages, bucket.messages, bucket.items.reverse ] },
        line.("complaint_share") do |bucket|
          [ ratio(bucket.complaints, bucket.sentiments), bucket.sentiments, bucket.complaint_items.reverse ]
        end,
        line.("mean_anger") do |bucket|
          angry = bucket.angry_items.sort_by { |anger, _| -anger }.map(&:last)
          [ ratio(bucket.angers.sum, bucket.angers.size), bucket.angers.size, angry ]
        end,
        *moods.map do |mood|
          line.("mood_share", mood) do |bucket|
            in_mood = bucket.customers.values.select { |customer_mood, _| customer_mood == mood }.map(&:last).reverse
            [ ratio(in_mood.size, bucket.customers.size), bucket.customers.size, in_mood ]
          end
        end,
        *categories.map do |category_id|
          line.("category_volume", category_id.to_s) do |bucket|
            items = bucket.categories.fetch(category_id, [])
            [ items.size, items.size, items.reverse ]
          end
        end
      ]
    end

    def ratio(numerator, denominator)
      denominator.zero? ? nil : numerator.to_f / denominator
    end

    # The same person across threads, matching MoodScene: email first, then a handle within its source kind.
    def customer_key(item_id, email, handle, name, source_kind)
      if email.present? then "email:#{email.strip.downcase}"
      elsif handle.present? then "#{source_kind}:#{handle.strip.downcase}"
      elsif name.present? then "#{source_kind}:name:#{name.strip.downcase}"
      else "item:#{item_id}"
      end
    end
  end
end
