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
      within_app do
        parent_channel_id = thread_parent_id(payload["channel_id"])
        Connectors::Discord.ingest(payload, parent_channel_id: parent_channel_id)
      rescue StandardError => error
        log_failure("message #{payload["id"]}", error)
        Source.for(:discord, parent_channel_id || payload["channel_id"])&.record_error!(error)
      end
    end

    def handle_connected
      within_app { Connectors::Discord.clear_gateway_errors! }
    end

    def handle_disconnected
      within_app { Connectors::Discord.record_gateway_error!("disconnected, reconnecting") }
    end

    private

    # Channels and active threads arrive in the gateway's guild payloads, so this
    # is a cache hit except for a thread the bot has not seen yet.
    def thread_parent_id(channel_id)
      return if channel_id.blank? || Source.discord.exists?(selector: channel_id)

      channel = @bot.channel(channel_id.to_i)
      channel.parent_id.to_s if channel&.thread? && channel.parent_id
    end

    # Handlers run on discordrb's event threads, which log anything that escapes.
    def within_app(&block)
      Rails.application.executor.wrap(&block)
    end

    def log_failure(label, error)
      @logger.error("[discord] #{label} failed: #{error.class}: #{error.message}")
    end
  end
end
