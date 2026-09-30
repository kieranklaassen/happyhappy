require "net/http"

module Slack
  # Calls the Slack Web API with the bot token (chat:write, channels:join, users:read, users:read.email).
  #
  #   ts = Slack::Client.new.post_message(channel: "C0CORASUPPORT", text: "fallback", blocks: [...])
  #   Slack::Client.new.post_message(channel: "C0CORASUPPORT", text: "reply", thread_ts: ts)
  #   Slack::Client.new.update_message(channel: "C0CORASUPPORT", ts: ts, text: "fallback", blocks: [...])
  #
  # Raises RetryableError for rate limits, Slack 5xx, and network failures, and
  # Error for everything else (bad channel, bad token, missing token). Error#code
  # holds Slack's error string, such as "not_in_channel".
  class Client
    class Error < StandardError
      attr_reader :code

      def initialize(message = nil, code: nil)
        super(message)
        @code = code
      end
    end
    class RetryableError < Error; end

    API = "https://slack.com/api".freeze
    POST_MESSAGE_URL = URI("#{API}/chat.postMessage").freeze
    RETRYABLE_API_ERRORS = %w[ratelimited internal_error fatal_error service_unavailable request_timeout].freeze
    NETWORK_ERRORS = [ Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      SocketError, OpenSSL::SSL::SSLError, EOFError ].freeze

    def initialize(token: ENV["SLACK_BOT_TOKEN"])
      @token = token
    end

    def post_message(channel:, text:, blocks: nil, thread_ts: nil)
      call("chat.postMessage", { channel:, text:, blocks:, thread_ts: }.compact).fetch("ts")
    end

    def update_message(channel:, ts:, text:, blocks:)
      call("chat.update", { channel:, ts:, text:, blocks: })
    end

    # Public channels only (channels:join); a private channel needs the bot invited.
    def join(channel:)
      call("conversations.join", { channel: }, form: true)
    end

    # Posts, joining the channel and retrying once when the bot is not a member yet.
    def post_message_joining(channel:, **message)
      post_message(channel:, **message)
    rescue Error => error
      raise unless error.code == "not_in_channel"

      join(channel:)
      post_message(channel:, **message)
    end

    def user_info(user:)
      call("users.info", { user: }, form: true).fetch("user")
    end

    private

    # Read methods such as users.info only take form bodies; chat methods take JSON for their blocks.
    def call(method, payload, form: false)
      raise Error, "SLACK_BOT_TOKEN is not set" if @token.blank?

      parse(request(URI("#{API}/#{method}"), payload, form:))
    end

    def request(uri, payload, form:)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      if form
        request.set_form_data(payload)
      else
        request["Content-Type"] = "application/json; charset=utf-8"
        request.body = payload.to_json
      end
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
      raise (RETRYABLE_API_ERRORS.include?(error) ? RetryableError : Error).new("Slack: #{error}", code: error)
    rescue JSON::ParserError
      raise RetryableError, "Slack returned an unreadable response"
    end
  end
end
