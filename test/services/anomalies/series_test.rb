require "test_helper"

class Anomalies::SeriesTest < ActiveSupport::TestCase
  include AnomalyHelper

  setup do
    @windows = Anomalies::Detect.windows("hour", now: anomaly_now).last(3)
    @last = @windows.last.first
  end

  def lines
    Anomalies::Series.new(windows: @windows, granularity: "hour").lines
  end

  def line(metric, source: nil, dimension: nil, product: products(:cora))
    lines.find do |candidate|
      candidate.product_id == product.id && candidate.source_id == source&.id &&
        candidate.metric == metric && candidate.dimension == dimension
    end
  end

  test "builds every metric per product and per product plus source" do
    complaint = customer_message!(at: @last + 1.minute, sentiment: "complaint", anger: 0.9, category: categories(:bug),
      author: "ana")
    customer_message!(at: @last + 2.minutes, sentiment: "praise", anger: 0.1, author: "bo", source: sources(:intercom_inbox))
    customer_message!(at: @last + 3.minutes, sentiment: "question", anger: 0.2, author: "cy")

    volume = line("volume").points.last
    assert_equal 3, volume.value
    assert_equal 3, volume.item_ids.size

    complaints = line("complaint_share").points.last
    assert_in_delta 1.0 / 3, complaints.value
    assert_equal 3, complaints.count
    assert_equal [ complaint.item_id ], complaints.item_ids

    anger = line("mean_anger").points.last
    assert_in_delta 0.4, anger.value
    assert_equal [ complaint.item_id ], anger.item_ids

    furious = line("mood_share", dimension: "furious").points.last
    assert_in_delta 1.0 / 3, furious.value
    assert_equal 3, furious.count

    bugs = line("category_volume", dimension: categories(:bug).id.to_s).points.last
    assert_equal 1, bugs.value
    assert_equal [ complaint.item_id ], bugs.item_ids

    assert_equal 1, line("volume", source: sources(:intercom_inbox)).points.last.value
    assert_equal 2, line("volume", source: sources(:slack_community)).points.last.value
  end

  test "counts zero volume in empty windows and a nil ratio with no data" do
    customer_message!(at: @last + 1.minute)

    first = line("volume").points.first
    assert_equal 0, first.value
    assert_nil line("complaint_share").points.first.value
    assert_equal 2, line("volume").first_index
  end

  test "every line has one point per window, in order, when messages are sparse" do
    first = @windows.first.first
    bug = customer_message!(at: first + 1.minute, sentiment: "complaint", anger: 0.9, category: categories(:bug), author: "ana")
    older = customer_message!(at: @last + 1.minute, sentiment: "praise", anger: 0.1, category: categories(:praise), author: "bo")
    newer = customer_message!(at: @last + 2.minutes, sentiment: "praise", anger: 0.1, category: categories(:praise), author: "cy")

    lines.each do |candidate|
      assert_equal @windows, candidate.points.map { |point| [ point.window_start, point.window_end ] },
        [ candidate.metric, candidate.dimension ].inspect
      empty = candidate.points.second
      assert_equal [ candidate.count_metric? ? 0 : nil, 0, [] ], [ empty.value, empty.count, empty.item_ids ]
    end

    assert_equal [ 1, 0, 0 ], line("category_volume", dimension: categories(:bug).id.to_s).points.map(&:value)
    assert_equal [ 0, 0, 2 ], line("category_volume", dimension: categories(:praise).id.to_s).points.map(&:value)
    assert_equal [ 1, 0, 2 ], line("volume").points.map(&:count)
    assert_equal [ 1.0, nil, 0.0 ], line("mood_share", dimension: "furious").points.map(&:value)
    assert_equal [ 0.0, nil, 1.0 ], line("mood_share", dimension: "beaming").points.map(&:value)
    assert_equal [ [ bug.item_id ], [], [] ], line("mood_share", dimension: "furious").points.map(&:item_ids)
    assert_equal [ newer.item_id, older.item_id ], line("mood_share", dimension: "beaming").points.last.item_ids
  end

  test "each customer counts once, by their latest message in the window" do
    customer_message!(at: @last + 1.minute, sentiment: "complaint", anger: 0.95, author: "ana")
    customer_message!(at: @last + 5.minutes, sentiment: "praise", anger: 0.0, author: "ana")

    assert_equal 1, line("mood_share", dimension: "beaming").points.last.count
    assert_in_delta 1.0, line("mood_share", dimension: "beaming").points.last.value
    assert_in_delta 0.0, line("mood_share", dimension: "furious").points.last.value
  end

  test "leaves out unclassified messages from ratios, not relevant items, and items with no product" do
    customer_message!(at: @last + 1.minute, classified: false, sentiment: nil, anger: nil)
    customer_message!(at: @last + 2.minutes).item.update!(relevant: false)
    customer_message!(at: @last + 3.minutes, product: products(:cora)).item.update!(product: nil)

    assert_equal 1, line("volume").points.last.value
    assert_equal 0, line("complaint_share").points.last.count
  end

  test "an unknown mood becomes its own mood share" do
    customer_message!(at: @last + 1.minute, author: "ana")
    original = Mood.method(:for)
    Mood.define_singleton_method(:for) { |**| "relieved" }

    assert_in_delta 1.0, line("mood_share", dimension: "relieved").points.last.value
    assert_in_delta 0.0, line("mood_share", dimension: "beaming").points.last.value
  ensure
    Mood.define_singleton_method(:for, original)
  end

  test "counts customer messages and authors nobody has placed yet, never the team" do
    customer_message!(at: @last + 1.minute, author_role: "customer")
    customer_message!(at: @last + 2.minutes, author_role: "team")
    customer_message!(at: @last + 3.minutes, author_role: "unknown")

    assert_equal 2, line("volume").points.last.value
  end
end
