require "test_helper"

class OverviewDigestTest < ActiveSupport::TestCase
  test "requires date" do
    digest = OverviewDigest.new(date: nil)

    assert_not digest.valid?
    assert digest.errors.key?(:date)
  end

  test "allows at most one overview digest per date" do
    date = Date.new(2030, 2, 1)
    OverviewDigest.create!(date: date)

    duplicate = OverviewDigest.new(date: date)
    assert_not duplicate.valid?
    assert duplicate.errors.key?(:date)

    other_day = OverviewDigest.new(date: date + 1.day)
    assert other_day.valid?

    assert_raises(ActiveRecord::RecordNotUnique) do
      OverviewDigest.new(date: date).save(validate: false)
    end
  end

  test "posted? reflects whether posted_at is present" do
    unposted = OverviewDigest.new(
      date: Date.new(2030, 2, 2),
      slack_message_ts: "1727200000.000100",
      last_error: "Slack: channel_not_found"
    )
    assert_not unposted.posted?

    posted = OverviewDigest.new(date: Date.new(2030, 2, 2), posted_at: Time.current)
    assert posted.posted?
  end
end
