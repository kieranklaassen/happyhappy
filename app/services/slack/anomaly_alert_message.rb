module Slack
  # Block Kit payload for an urgent alert about a new negative, high-severity
  # anomaly: what spiked, a link to the product overview, and a few of the
  # customers behind it.
  #
  #   Slack::AnomalyAlertMessage.new(anomaly).to_h # => { text:, blocks: }
  class AnomalyAlertMessage
    include Formatting
    include AnomalyWording

    EXAMPLE_COUNT = 3

    def initialize(anomaly)
      @anomaly = anomaly
    end

    def to_h
      {
        text: "#{@anomaly.product.name}: #{@anomaly.label.to_s.downcase_first} spiked",
        blocks: [
          section("#{anomaly_line(@anomaly)}\n#{link(overview_url, "Open the #{@anomaly.product.name} overview")}"),
          (section("*Customers behind it*\n#{examples_text}") if examples.any?),
          context("#{window_text} · #{@anomaly.granularity == "hour" ? "hourly" : "daily"} check")
        ].compact
      }
    end

    private

    def examples
      @examples ||= Item.where(id: @anomaly.item_ids).by_actionability.limit(EXAMPLE_COUNT).to_a
    end

    def examples_text
      examples.map do |item|
        body = item.messages.from_customers.last&.body
        "#{link(item_url(item), customer_handle(item))}\n#{quote(body)}"
      end.join("\n")
    end

    def overview_url
      "#{ENV.fetch("PUBLIC_BASE_URL", "http://localhost:3000").chomp("/")}/products/#{@anomaly.product_id}/overview"
    end

    def window_text
      zone = Setting.current.digest_zone
      from = @anomaly.window_start.in_time_zone(zone)
      to = @anomaly.window_end.in_time_zone(zone)
      "#{from.strftime("%b %-d %H:%M")} to #{to.strftime("%H:%M %Z")}"
    end
  end
end
