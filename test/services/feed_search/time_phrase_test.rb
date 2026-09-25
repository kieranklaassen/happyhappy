require "test_helper"

class FeedSearch::TimePhraseTest < ActiveSupport::TestCase
  NOW = Time.zone.parse("2026-09-24 15:00") # a Thursday

  def extract(query)
    FeedSearch::TimePhrase.extract(query, now: NOW)
  end

  test "pulls the phrase out and leaves the rest of the query" do
    text, time = extract("angry Cora billing this week")

    assert_equal "angry Cora billing", text
    assert_equal "This week", time.name
    assert_equal({ since: Time.zone.parse("2026-09-21 00:00").iso8601 }, time.filters)
    assert_equal({ key: "time", label: "time", kind: "filter", name: "This week" }, time.chip)
  end

  test "closed windows carry an until" do
    _, yesterday = extract("yesterday praise")
    _, last_week = extract("refunds last week")

    assert_equal({ since: Time.zone.parse("2026-09-23 00:00").iso8601, until: Time.zone.parse("2026-09-24 00:00").iso8601 },
      yesterday.filters)
    assert_equal Time.zone.parse("2026-09-14 00:00"), last_week.since
    assert_equal Time.zone.parse("2026-09-21 00:00"), last_week.until
  end

  test "counts of days and hours" do
    assert_equal [ "Last 3 days", NOW - 3.days ], extract("in the past 3 days bugs").last.then { |time| [ time.name, time.since ] }
    assert_equal NOW - 12.hours, extract("last 12 hours").last.since
  end

  test "a query without a time phrase is only squished" do
    assert_equal [ "needs action now", nil ], extract("  needs  action now ")
    assert_equal [ "thisweekly", nil ], extract("thisweekly")
  end
end
