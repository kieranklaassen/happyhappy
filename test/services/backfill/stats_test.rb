require "test_helper"

class Backfill::StatsTest < ActiveSupport::TestCase
  setup do
    @source = sources(:discord_spiral)
    @stats = Backfill::Stats.new(@source)
  end

  test "initializes counters to zero and error to nil" do
    assert_equal @source, @stats.source
    assert_equal 0, @stats.fetched
    assert_equal 0, @stats.created
    assert_equal 0, @stats.duplicates
    assert_equal 0, @stats.skipped
    assert_nil @stats.error
  end

  test "record counts created and duplicate results and ignores nil" do
    created_result = Items::Ingest::Result.new(item: nil, message: nil, duplicate: false)
    duplicate_result = Items::Ingest::Result.new(item: nil, message: nil, duplicate: true)

    @stats.record(nil)
    @stats.record(created_result)
    @stats.record(created_result)
    @stats.record(duplicate_result)

    assert_equal 2, @stats.created
    assert_equal 1, @stats.duplicates
  end

  test "skipped returns fetched messages neither created nor duplicated" do
    @stats.fetched = 10
    @stats.created = 4
    @stats.duplicates = 3

    assert_equal 3, @stats.skipped
  end

  test "to_s formats summary counts and appends error only when present" do
    @stats.fetched = 7
    @stats.created = 3
    @stats.duplicates = 2

    expected = "source #{@source.id} #{@source.name}: fetched=7 created=3 duplicates=2 skipped=2"
    assert_equal expected, @stats.to_s

    @stats.error = "HTTP 429"
    assert_equal "#{expected} error=HTTP 429", @stats.to_s
  end
end
