module Connectors
  # Polls X recent search for one X source and ingests each post as a message
  # on its conversation's item.
  #
  #   Connectors::X.poll(source)
  class X
    BASE_URL = "https://api.x.com"
    SEARCH_PATH = "/2/tweets/search/recent"
    SEARCH_FIELDS = {
      "expansions" => "author_id",
      "tweet.fields" => "author_id,conversation_id,created_at",
      "user.fields" => "name,username"
    }.freeze

    class Error < StandardError; end

    def self.bearer_token
      ENV["X_BEARER_TOKEN"].presence
    end

    def self.poll(source, token: bearer_token, now: Time.current)
      new(source, token: token, now: now).poll
    end

    def initialize(source, token:, now: Time.current)
      @source = source
      @token = token
      @budget = XBudget.new(source, now: now)
    end

    def poll
      @budget.roll_month!
      return @source.record_error!("X_BEARER_TOKEN is not set") unless @token
      return unless @budget.permit!

      pages = []
      loop do
        pages << search(max_results: @budget.affordable_max_results, next_token: pages.last&.dig("meta", "next_token"))
        break unless pages.last.dig("meta", "next_token") && @budget.permit!
      end
      # Pages and posts arrive newest first; oldest first lets a conversation's
      # root post create its item before the replies.
      pages.reverse_each { |page| ingest(page) }
      newest_id = pages.first.dig("meta", "newest_id")
      @source.update!(since_id: newest_id || @source.since_id, last_error: nil, last_error_at: nil)
    rescue Error, Faraday::Error => error
      @source.record_error!(error)
    end

    private

    def search(max_results:, next_token:)
      params = SEARCH_FIELDS.merge("query" => @source.selector, "max_results" => max_results,
        "since_id" => @source.since_id, "next_token" => next_token).compact
      response = connection.get(SEARCH_PATH, params)
      raise Error, "X search failed with HTTP #{response.status}: #{error_detail(response)}" unless response.success?

      page = JSON.parse(response.body)
      @budget.record_spend!(posts: Array(page["data"]).size, users: Array(page.dig("includes", "users")).size)
      page
    rescue JSON::ParserError => error
      raise Error, "X search returned invalid JSON: #{error.message}"
    end

    def ingest(page)
      users = Array(page.dig("includes", "users")).index_by { |user| user["id"] }
      Array(page["data"]).reverse_each do |post|
        Items::Ingest.call(source: @source, inbound: inbound_message(post, users[post["author_id"]]))
      end
    end

    def inbound_message(post, author)
      username = author&.dig("username")
      Items::InboundMessage.new(
        external_id: post["id"],
        thread_key: post["conversation_id"].presence || post["id"],
        body: post["text"],
        occurred_at: post["created_at"],
        author_handle: username,
        author_name: author&.dig("name"),
        permalink: username ? "https://x.com/#{username}/status/#{post["id"]}" : "https://x.com/i/web/status/#{post["id"]}",
        raw_payload: { "post" => post, "author" => author }.compact
      )
    end

    def error_detail(response)
      body = JSON.parse(response.body)
      body["detail"] || body["title"] || Array(body["errors"]).first&.dig("message") || "no detail"
    rescue JSON::ParserError
      "no detail"
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL, request: { open_timeout: 5, timeout: 15 }) do |faraday|
        faraday.request :authorization, "Bearer", @token
      end
    end
  end
end
