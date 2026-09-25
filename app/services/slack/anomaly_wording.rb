module Slack
  # One line per anomaly, worded by polarity: good news is sunshine, bad news
  # carries its severity, and neutral changes are just reported.
  #
  #   anomaly_line(anomaly)
  #   # => ":warning: *Sparkle*: billing messages spiked (8 vs about 0.2 usual, high)"
  module AnomalyWording
    include Formatting

    private

    def anomaly_line(anomaly)
      product = "*#{escape(anomaly.product.name)}*"
      what = escape(anomaly.label.to_s.downcase_first)
      where = anomaly.source ? " on #{escape(anomaly.source.name)}" : ""
      numbers = "#{anomaly_value(anomaly, anomaly.actual)} vs about #{anomaly_value(anomaly, anomaly.expected)} usual"

      case anomaly.polarity
      when "positive" then ":sunny: Good news for #{product}: #{what} up#{where} (#{numbers})"
      when "negative" then ":warning: #{product}: #{what} spiked#{where} (#{numbers}, #{anomaly.severity})"
      else "#{product}: #{what} up#{where} (#{numbers})"
      end
    end

    def anomaly_value(anomaly, value)
      return percent(value) if anomaly.share?

      rounded = value.to_f.round(1)
      rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
    end
  end
end
