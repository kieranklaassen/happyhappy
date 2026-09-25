module Backfill
  # Imports customer messages from Intercom conversations updated since a cutoff:
  # searches conversations by updated_at, fetches each one with its parts, and
  # replays the customer-authored messages written since the cutoff through
  # Connectors::Intercom as backfill. Routing and dedupe match the webhook, so a
  # rerun creates nothing new. Needs INTERCOM_ACCESS_TOKEN (Developer Hub,
  # Authentication), which is separate from the webhook's client secret.
  #
  #   Backfill::Intercom.call(since: 90.days.ago) # => [Backfill::Stats, ...]
  class Intercom
    API_URL = "https://api.intercom.io"
    API_VERSION = "2.16"
    PAGE_SIZE = 150

    attr_reader :conversations

    def self.call(...)
      new(...).call
    end

    PROGRESS_EVERY = 100

    # progress, when given, is called with the number of conversations scanned
    # every PROGRESS_EVERY conversations.
    def initialize(since:, token: ENV["INTERCOM_ACCESS_TOKEN"], sleeper: nil, progress: nil)
      raise ArgumentError, "INTERCOM_ACCESS_TOKEN is not set" if token.to_s.strip.empty?

      @since = since
      @progress = progress
      @http = HttpClient.new(base_url: API_URL,
        headers: { "Authorization" => "Bearer #{token.strip}", "Intercom-Version" => API_VERSION },
        throttle: method(:throttle), **{ sleeper: sleeper }.compact)
      @stats = {}
      @conversations = 0
    end

    def call
      app_id = @http.get("/me").dig("app", "id_code")
      each_conversation_id do |id|
        @conversations += 1
        @progress&.call(@conversations) if (@conversations % PROGRESS_EVERY).zero?
        conversation = @http.get("/conversations/#{id}")
        Connectors::Intercom.ingest_conversation(conversation, app_id: app_id, since: @since).each do |result|
          stats_for(result.message.source).tap do |stats|
            stats.fetched += 1
            stats.record(result)
          end
        end
      end
      @stats.values
    end

    private

    def each_conversation_id
      starting_after = nil
      loop do
        page = @http.post("/conversations/search", {
          query: { field: "updated_at", operator: ">", value: @since.to_i },
          pagination: { per_page: PAGE_SIZE, starting_after: starting_after }.compact
        })
        page.fetch("conversations", []).each { |conversation| yield conversation["id"] }
        starting_after = page.dig("pages", "next", "starting_after")
        break if starting_after.blank?
      end
    end

    def stats_for(source)
      @stats[source.id] ||= Stats.new(source)
    end

    # https://developers.intercom.com/docs/references/rest-api/errors/rate-limiting
    def throttle(response)
      return unless response.status == 429 || response.headers["x-ratelimit-remaining"] == "0"

      reset = response.headers["x-ratelimit-reset"].to_i
      reset.positive? ? [ reset - Time.current.to_i, 1 ].max.to_f : nil
    end
  end
end
