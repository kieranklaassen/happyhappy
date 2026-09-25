require "test_helper"

class Classification::RateLimiterTest < ActiveSupport::TestCase
  setup do
    @now = 1_000.2
    @sleeps = []
    @cache = ActiveSupport::Cache::MemoryStore.new
    @fake = FakeClassifier.new
    @message = messages(:unclassified_slack_reply)
  end

  test "lets a second's share of the minute's budget through without waiting" do
    limiter = limiter(per_minute: 180)

    3.times { limiter.call(@message) }

    assert_equal 3, @fake.calls.size
    assert_empty @sleeps
  end

  test "makes the call over budget wait for the next second" do
    limiter = limiter(per_minute: 120)

    3.times { limiter.call(@message) }

    assert_equal 3, @fake.calls.size
    assert_equal 1, @sleeps.size
    assert_in_delta 0.8, @sleeps.sole
  end

  test "defaults to TypeSafe's 1,200 requests a minute, or TYPESAFE_REQUESTS_PER_MINUTE" do
    assert_equal 1_200, Classification::RateLimiter.per_minute

    with_env("TYPESAFE_REQUESTS_PER_MINUTE" => "600") { assert_equal 600, Classification::RateLimiter.per_minute }
  end

  test "gives up with Exhausted, which the job retries, when no slot opens in time" do
    saturated = Class.new { def increment(*) = 1_000 }.new
    limiter = limiter(per_minute: 60, cache: saturated, sleeper: ->(seconds) { @sleeps << seconds; @now += 10 })

    assert_raises(Classification::RateLimiter::Exhausted) { limiter.call(@message) }
    assert_empty @fake.calls
    assert_equal 3, @sleeps.size
    assert_includes ClassifyMessageJob::PROVIDER_ERRORS, Classification::RateLimiter::Exhausted
  end

  test "a cache that cannot count never blocks" do
    limiter = limiter(per_minute: 60, cache: ActiveSupport::Cache::NullStore.new)

    5.times { limiter.call(@message) }

    assert_equal 5, @fake.calls.size
    assert_empty @sleeps
  end

  test "wraps the production classifier but not a classifier set by tests" do
    Classification.classifier = nil
    assert_instance_of Classification::RateLimiter, Classification.classifier

    fake = use_fake_classifier
    assert_same fake, Classification.classifier
  end

  private

  def limiter(per_minute:, cache: @cache, sleeper: nil)
    sleeper ||= ->(seconds) { @sleeps << seconds; @now += seconds }
    Classification::RateLimiter.new(@fake, per_minute: per_minute, cache: cache, clock: -> { @now }, sleeper: sleeper)
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
