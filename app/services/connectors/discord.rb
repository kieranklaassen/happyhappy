module Connectors
  # Turns Discord gateway MESSAGE_CREATE payloads into items (KTD3). The payload
  # is the dispatch's `d` hash with string keys, exactly as the gateway sends it.
  #
  #   Connectors::Discord.inbound_message(payload) # => Items::InboundMessage or nil
  #   Connectors::Discord.ingest(payload)          # => Items::Ingest::Result or nil
  module Discord
    # Default and reply; joins, pins, boosts, and other system messages are skipped.
    MESSAGE_TYPES = [ 0, 19 ].freeze
    GATEWAY_ERROR_PREFIX = "Discord gateway"

    module_function

    def inbound_message(payload)
      return unless customer_message?(payload)

      body = message_body(payload)
      return if body.blank?

      channel_id = payload["channel_id"]
      message_id = payload["id"]
      author = payload["author"]

      Items::InboundMessage.new(
        external_id: message_id,
        thread_key: "#{channel_id}:#{replied_to_id(payload) || message_id}",
        body: body,
        occurred_at: payload["timestamp"],
        author_handle: author["username"],
        author_name: author["global_name"].presence || author["username"],
        permalink: jump_link(payload),
        raw_payload: payload
      )
    end

    def ingest(payload)
      source = Source.active.for(:discord, payload["channel_id"]) if payload["channel_id"]
      return unless source

      inbound = inbound_message(payload)
      return unless inbound

      inbound.thread_key = reply_chain_thread_key(payload) || inbound.thread_key
      Items::Ingest.call(source: source, inbound: inbound)
    end

    def record_gateway_error!(reason)
      Source.discord.find_each { |source| source.record_error!("#{GATEWAY_ERROR_PREFIX}: #{reason}") }
    end

    def clear_gateway_errors!
      Source.discord.where("last_error LIKE ?", "#{GATEWAY_ERROR_PREFIX}:%")
        .update_all(last_error: nil, last_error_at: nil)
    end

    def customer_message?(payload)
      author = payload["author"]
      author.is_a?(Hash) &&
        !author["bot"] && !author["system"] &&
        payload["webhook_id"].blank? &&
        payload["guild_id"].present? &&
        MESSAGE_TYPES.include?(payload["type"])
    end

    def message_body(payload)
      attachments = Array(payload["attachments"]).filter_map { |attachment| attachment["url"] }
      [ payload["content"].to_s.strip, *attachments ].compact_blank.join("\n")
    end

    def replied_to_id(payload)
      payload.dig("message_reference", "message_id") if payload["type"] == 19
    end

    def jump_link(payload)
      "https://discord.com/channels/#{payload["guild_id"]}/#{payload["channel_id"]}/#{payload["id"]}"
    end

    # A reply joins whatever item holds the message it answers, so a chain of
    # replies stays one item even when each reply points at the previous one.
    def reply_chain_thread_key(payload)
      parent_id = replied_to_id(payload)
      return unless parent_id

      Message.joins(:source).where(sources: { kind: "discord" })
        .find_by(external_id: parent_id)&.item&.thread_key
    end
  end
end
