require "discordrb"

module Connectors
  # The long-lived gateway connection behind bin/discord (KTD6). Run exactly one
  # per bot token; Discord delivers each message to every connected session.
  class DiscordBot
    # discordrb 3.8.0 names no MESSAGE_CONTENT intent and leaves it out of :all,
    # so without this bit every message arrives with empty content.
    MESSAGE_CONTENT_INTENT = 1 << 15
    INTENTS = [ :servers, :server_messages, MESSAGE_CONTENT_INTENT ].freeze

    def initialize(token:, logger: Rails.logger)
      @logger = logger
      @bot = Discordrb::Bot.new(token: token, intents: INTENTS)
      @bot.raw(type: :MESSAGE_CREATE) { |event| handle_message(event.data) }
      @bot.raw(type: /\A(READY|RESUMED)\z/) { handle_connected }
      @bot.disconnected { handle_disconnected }
    end

    def run
      @bot.run
    end

    def stop
      @bot.stop
    end

    def handle_message(payload)
      within_app { Connectors::Discord.ingest(payload) }
    rescue StandardError => error
      log_failure("message #{payload["id"]}", error)
      within_app { Source.for(:discord, payload["channel_id"])&.record_error!(error) }
    end

    def handle_connected
      within_app { Connectors::Discord.clear_gateway_errors! }
    end

    def handle_disconnected
      within_app { Connectors::Discord.record_gateway_error!("disconnected, reconnecting") }
    end

    private

    # Handlers run on discordrb's event threads, which log anything that escapes.
    def within_app(&block)
      Rails.application.executor.wrap(&block)
    end

    def log_failure(label, error)
      @logger.error("[discord] #{label} failed: #{error.class}: #{error.message}")
    end
  end
end
