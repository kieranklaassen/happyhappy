module Classification
  # Wraps a classifier so every process that calls TypeSafe (job workers, Puma
  # for sync custom webhooks, reruns) stays under one requests-per-minute budget
  # together. Calls are counted per second in Rails.cache, so a burst is spread
  # evenly instead of spending the minute's budget in its first seconds.
  #
  #   Classification::RateLimiter.new(Classification::Classifier.new).call(message)
  #
  # A cache that cannot count (the null store) never blocks. A call that cannot
  # get a slot within MAX_WAIT raises Exhausted, which ClassifyMessageJob retries.
  class RateLimiter
    DEFAULT_PER_MINUTE = 1_200
    MAX_WAIT = 30.seconds

    class Exhausted < StandardError; end

    def self.per_minute
      Integer(ENV["TYPESAFE_REQUESTS_PER_MINUTE"].presence || DEFAULT_PER_MINUTE)
    end

    def initialize(classifier, per_minute: self.class.per_minute, cache: Rails.cache,
      clock: -> { Process.clock_gettime(Process::CLOCK_REALTIME) }, sleeper: ->(seconds) { sleep(seconds) })
      @classifier = classifier
      @per_second = [ per_minute / 60, 1 ].max
      @cache = cache
      @clock = clock
      @sleeper = sleeper
    end

    def call(message)
      acquire!
      @classifier.call(message)
    end

    private

    def acquire!
      deadline = @clock.call + MAX_WAIT
      loop do
        now = @clock.call
        second = now.floor
        count = @cache.increment("typesafe/requests/#{second}", 1, expires_in: 1.minute)
        return if count.nil? || count <= @per_second
        raise Exhausted, "no TypeSafe request slot within #{MAX_WAIT.inspect}" if now >= deadline

        @sleeper.call(second + 1 - now)
      end
    end
  end
end
