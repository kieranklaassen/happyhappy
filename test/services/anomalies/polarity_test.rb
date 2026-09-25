require "test_helper"

class Anomalies::PolarityTest < ActiveSupport::TestCase
  include AnomalyHelper

  def polarity(metric, dimension = nil, item_ids: [])
    Anomalies::Polarity.for(metric: metric, dimension: dimension, item_ids: item_ids)
  end

  def items_with(*sentiments)
    sentiments.map { |sentiment| customer_message!(at: 1.hour.ago, sentiment: sentiment).item_id }
  end

  test "the praise category is positive" do
    assert_equal "positive", polarity("category_volume", categories(:praise).id.to_s)
  end

  test "bug, billing, and cancellation categories are negative" do
    cancellation = Category.create!(name: "Cancellation", position: 9)

    [ categories(:bug), categories(:billing), cancellation ].each do |category|
      assert_equal "negative", polarity("category_volume", category.id.to_s, item_ids: items_with("praise", "praise")), category.name
    end
  end

  test "happy moods are positive, grumpy and furious are negative, other moods are neutral" do
    %w[beaming content relieved].each { |mood| assert_equal "positive", polarity("mood_share", mood), mood }
    %w[grumpy furious].each { |mood| assert_equal "negative", polarity("mood_share", mood), mood }
    %w[meh wistful].each { |mood| assert_equal "neutral", polarity("mood_share", mood), mood }
  end

  test "complaint share and mean anger are negative" do
    assert_equal "negative", polarity("complaint_share")
    assert_equal "negative", polarity("mean_anger")
  end

  test "volume and other categories follow the sentiment mix of their items" do
    assert_equal "positive", polarity("volume", item_ids: items_with("praise", "relieved", "question"))
    assert_equal "negative", polarity("volume", item_ids: items_with("complaint", "complaint", "praise"))
    assert_equal "neutral", polarity("volume", item_ids: items_with("praise", "complaint"))
    assert_equal "neutral", polarity("volume")
    assert_equal "positive", polarity("category_volume", categories(:feature_request).id.to_s, item_ids: items_with("praise"))
    assert_equal "neutral", polarity("category_volume", categories(:other).id.to_s, item_ids: items_with("question", "neutral"))
  end

  test "grade gives severity to bad news, a highlight to good news, and neither to neutral" do
    assert_equal({ polarity: "negative", severity: "medium", highlight: nil },
      DetectedAnomaly.grade(metric: "complaint_share", dimension: nil, item_ids: [], level: 1))
    assert_equal({ polarity: "positive", severity: nil, highlight: "huge" },
      DetectedAnomaly.grade(metric: "mood_share", dimension: "beaming", item_ids: [], level: 2))
    assert_equal({ polarity: "neutral", severity: nil, highlight: nil },
      DetectedAnomaly.grade(metric: "volume", dimension: nil, item_ids: [], level: 0))
  end

  test "a positive anomaly has no severity, and a negative one needs one" do
    positive = create_anomaly!(metric: "mood_share", dimension: "beaming", polarity: "positive", severity: nil, highlight: "notable")
    assert_nil positive.to_props[:severity]
    assert_equal "notable", positive.to_props[:highlight]
    assert_equal "positive", positive.to_props[:polarity]

    stormy_good_news = DetectedAnomaly.new(polarity: "positive", severity: "high", highlight: "big")
    stormy_good_news.validate
    assert stormy_good_news.errors.added?(:severity, :present)

    mild_bad_news = DetectedAnomaly.new(polarity: "negative", severity: nil)
    mild_bad_news.validate
    assert mild_bad_news.errors.added?(:severity, :inclusion, value: nil)
  end
end
