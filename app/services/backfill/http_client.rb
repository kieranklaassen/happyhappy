module Backfill
  # JSON over HTTP for the backfill tasks, paced by the provider's rate-limit
  # headers. `throttle` maps a response to the seconds to wait before the next
  # request (or nil); a 429 waits that long and retries.
  #
  #   http = Backfill::HttpClient.new(base_url: "https://discord.com/api/v10",
  #     headers: { "Authorization" => "Bot ..." }, throttle: ->(response) { ... })
  #   http.get("/channels/1/messages", limit: 100)
  class HttpClient
    class Error < StandardError; end

    MAX_ATTEMPTS = 6
    DEFAULT_RETRY_SECONDS = 1.0

    def initialize(base_url:, headers:, throttle:, sleeper: ->(seconds) { sleep(seconds) })
      @connection = Faraday.new(url: base_url, headers: headers.merge("Accept" => "application/json"))
      @throttle = throttle
      @sleeper = sleeper
    end

    def get(path, params = {})
      request { @connection.get(path.delete_prefix("/"), params.compact) }
    end

    def post(path, body)
      request do
        @connection.post(path.delete_prefix("/"), JSON.generate(body), "Content-Type" => "application/json")
      end
    end

    private

    def request
      attempts = 0
      loop do
        attempts += 1
        response = yield
        wait = @throttle.call(response)

        if response.status == 429
          raise Error, "rate limited after #{attempts} attempts" if attempts >= MAX_ATTEMPTS

          @sleeper.call(wait || DEFAULT_RETRY_SECONDS)
          next
        end

        @sleeper.call(wait) if wait&.positive?
        raise Error, "#{response.env.method.upcase} #{response.env.url.path} returned #{response.status}" unless response.success?

        return response.body.to_s.empty? ? {} : JSON.parse(response.body)
      end
    end
  end
end
