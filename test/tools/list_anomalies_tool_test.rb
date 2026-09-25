require "test_helper"

class ListAnomaliesToolTest < ActiveSupport::TestCase
  include AnomalyHelper

  def call(**arguments)
    ListAnomaliesTool.call(server_context: { agent: agents(:cursor) }, **arguments)
  end

  setup do
    @active = create_anomaly!
    @ended = create_anomaly!(product: products(:spiral), metric: "volume", dimension: nil, status: :ended,
      window_start: 2.days.ago, window_end: 2.days.ago + 1.hour, ended_at: 1.day.ago)
  end

  test "lists active anomalies with expected, actual, and driving items" do
    anomalies = call.structured_content["anomalies"]

    assert_equal [ @active.id ], anomalies.map { |anomaly| anomaly["id"] }
    assert_equal "Bug messages", anomalies.first["label"]
    assert_equal 0.4, anomalies.first["expected"]
    assert_equal 9.0, anomalies.first["actual"]
    assert_equal [ items(:angry_slack).id ], anomalies.first["item_ids"]
    assert_equal "cora", anomalies.first.dig("product", "slug")
  end

  test "filters by status and product" do
    assert_equal [ @active.id, @ended.id ], call(status: "all").structured_content["anomalies"].map { |anomaly| anomaly["id"] }
    assert_equal [ @ended.id ], call(status: "ended", product: "spiral").structured_content["anomalies"].map { |anomaly| anomaly["id"] }
  end

  test "carries polarity, severity for bad news only, and a highlight for good news, and filters by polarity" do
    praise = create_anomaly!(dimension: categories(:praise).id.to_s, polarity: "positive", severity: nil, highlight: "big")

    anomalies = call.structured_content["anomalies"].index_by { |anomaly| anomaly["id"] }
    assert_equal({ "polarity" => "negative", "severity" => "high", "highlight" => nil }, anomalies[@active.id].slice("polarity", "severity", "highlight"))
    assert_equal({ "polarity" => "positive", "severity" => nil, "highlight" => "big" }, anomalies[praise.id].slice("polarity", "severity", "highlight"))
    assert anomalies[praise.id].key?("severity")
    assert_equal [ praise.id ], call(polarity: "positive").structured_content["anomalies"].map { |anomaly| anomaly["id"] }
  end

  test "an unknown product or status is a tool error" do
    assert call(product: "nope").error?
    assert_equal "Invalid filter status: must be one of active, ended, all", call(status: "open").content.first[:text]
  end
end
