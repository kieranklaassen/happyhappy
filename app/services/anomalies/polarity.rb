module Anomalies
  # Whether an anomaly is good news, bad news, or neither, from its metric and dimension. Volume and
  # categories with no built-in reading follow the sentiment mix of the items that drove the spike.
  #
  #   Anomalies::Polarity.for(metric: "category_volume", dimension: "5", item_ids: [ 1, 2 ])  # => "positive"
  module Polarity
    ALL = %w[positive negative neutral].freeze
    POSITIVE_MOODS = %w[beaming content relieved].freeze
    NEGATIVE_MOODS = %w[grumpy furious].freeze
    POSITIVE_CATEGORIES = %w[praise].freeze
    NEGATIVE_CATEGORIES = %w[bug billing cancellation].freeze
    POSITIVE_SENTIMENTS = %w[praise relieved].freeze

    module_function

    def for(metric:, dimension:, item_ids:)
      case metric
      when "complaint_share", "mean_anger" then "negative"
      when "mood_share"
        if dimension.in?(POSITIVE_MOODS) then "positive"
        elsif dimension.in?(NEGATIVE_MOODS) then "negative"
        else "neutral"
        end
      when "category_volume"
        name = Category.find_by(id: dimension)&.name.to_s.downcase
        if name.in?(POSITIVE_CATEGORIES) then "positive"
        elsif name.in?(NEGATIVE_CATEGORIES) then "negative"
        else from_items(item_ids)
        end
      else from_items(item_ids)
      end
    end

    def from_items(item_ids)
      sentiments = Item.where(id: item_ids).pluck(:sentiment)
      return "neutral" if sentiments.empty?

      majority = sentiments.size / 2.0
      if sentiments.count { |sentiment| sentiment.in?(POSITIVE_SENTIMENTS) } > majority then "positive"
      elsif sentiments.count("complaint") > majority then "negative"
      else "neutral"
      end
    end
  end
end
