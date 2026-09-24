require "net/http"

module Slack
  # Posts Block Kit messages with the bot token (chat:write scope).
  #
  #   ts = Slack::Client.new.post_message(channel: "C0CORASUPPORT", text: "fallback", blocks: [...])
  #
  # Raises RetryableError for rate limits, Slack 5xx, and network failures, and
  # Error for everything else (bad channel, bad token, missing token).
  class Client
    class Error < StandardError; end
    class RetryableError < Error; end

    POST_MESSAGE_URL = URI("https://slack.com/api/chat.postMessage").freeze
    RETRYABLE_API_ERRORS = %w[ratelimited internal_error fatal_error service_unavailable request_timeout].freeze
    NETWORK_ERRORS = [ Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      SocketError, OpenSSL::SSL::SSLError, EOFError ].freeze

    def initialize(token: ENV["SLACK_BOT_TOKEN"])
      @token = token
    end

    def post_message(channel:, text:, blocks:)
      raise Error, "SLACK_BOT_TOKEN is not set" if @token.blank?

      body = parse(request(channel: channel, text: text, blocks: blocks))
      body.fetch("ts")
    end

    private

    def request(payload)
      http = Net::HTTP.new(POST_MESSAGE_URL.host, POST_MESSAGE_URL.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(POST_MESSAGE_URL)
      request["Authorization"] = "Bearer #{@token}"
      request["Content-Type"] = "application/json; charset=utf-8"
      request.body = payload.to_json
      http.request(request)
    rescue *NETWORK_ERRORS => error
      raise RetryableError, "Slack unreachable: #{error.class}: #{error.message}"
    end

    def parse(response)
      status = response.code.to_i
      raise RetryableError, "Slack HTTP #{status}" if status == 429 || status >= 500
      raise Error, "Slack HTTP #{status}" unless status == 200

      body = JSON.parse(response.body)
      return body if body["ok"]

      error = body["error"].presence || "unknown_error"
      raise(RETRYABLE_API_ERRORS.include?(error) ? RetryableError : Error, "Slack: #{error}")
    rescue JSON::ParserError
      raise RetryableError, "Slack returned an unreadable response"
    end
  end
end
