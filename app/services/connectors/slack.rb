module Connectors
  # Maps Slack Events API message events from public channels onto Items::Ingest.
  #
  #   Connectors::Slack.ingestible?(envelope) # cheap check before enqueueing
  #   Connectors::Slack.new.ingest(envelope)  # => Items::Ingest::Result or nil
  #
  # Author and permalink lookups degrade to the user id and an archive link when
  # Slack refuses or is down, so a message is never dropped for missing metadata.
  class Slack
    INGESTED_SUBTYPES = [ nil, "thread_broadcast", "file_share" ].freeze
    LOOKUP_TTL = 1.day

    def self.ingestible?(envelope)
      customer_message?(envelope) && active_source_for(envelope["event"]).present?
    end

    def self.customer_message?(envelope)
      event = envelope["event"]
      envelope["type"] == "event_callback" &&
        event.is_a?(Hash) &&
        event["type"] == "message" &&
        event["channel_type"] == "channel" &&
        INGESTED_SUBTYPES.include?(event["subtype"]) &&
        event["bot_id"].blank? &&
        event["ts"].present? &&
        event["user"].present? &&
        Array(envelope["authorizations"]).none? { |auth| auth["is_bot"] && auth["user_id"] == event["user"] }
    end

    def self.active_source_for(event)
      Source.for(:slack, event["channel"])&.then { |source| source if source.active? }
    end

    def initialize(client: ::Slack::Web::Client.new(token: ENV["SLACK_BOT_TOKEN"]), cache: Rails.cache)
      @client = client
      @cache = cache
    end

    def ingest(envelope)
      return unless self.class.customer_message?(envelope)

      event = envelope["event"]
      source = self.class.active_source_for(event) or return
      channel, ts = event.values_at("channel", "ts")
      inbound = Items::InboundMessage.new(
        external_id: "#{channel}:#{ts}",
        thread_key: "#{channel}:#{event["thread_ts"].presence || ts}",
        body: event["text"],
        occurred_at: Time.zone.at(ts.to_r),
        raw_payload: event
      )

      @lookup_errors = []
      inbound.assign_attributes(lookups(event["user"], channel, ts)) unless source.messages.exists?(external_id: inbound.external_id)

      result = Items::Ingest.call(source: source, inbound: inbound)
      source.record_error!(@lookup_errors.join("; ")) if @lookup_errors.any?
      result
    end

    private

    def lookups(user_id, channel, ts)
      author = author_for(user_id)
      { author_handle: author["handle"], author_name: author["name"], author_email: author["email"],
        permalink: permalink_for(channel, ts) }
    end

    def author_for(user_id)
      @cache.fetch("slack/users/#{user_id}", expires_in: LOOKUP_TTL) do
        user = @client.users_info(user: user_id).user
        { "handle" => user.name, "name" => user.profile&.display_name.presence || user.real_name,
          "email" => user.profile&.email }
      end
    rescue Faraday::Error => error
      lookup_failed("users.info", error)
      { "handle" => user_id }
    end

    def permalink_for(channel, ts)
      @cache.fetch("slack/permalinks/#{channel}/#{ts}", expires_in: LOOKUP_TTL) do
        @client.chat_getPermalink(channel: channel, message_ts: ts).permalink
      end
    rescue Faraday::Error => error
      lookup_failed("chat.getPermalink", error)
      "https://slack.com/archives/#{channel}/p#{ts.delete(".")}"
    end

    def lookup_failed(method, error)
      Rails.logger.warn("[slack] #{method} failed: #{error.class}: #{error.message}")
      @lookup_errors << "Slack #{method}: #{error.message}"
    end
  end
end
