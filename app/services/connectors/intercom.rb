module Connectors
  # Maps Intercom webhook notifications to inbound messages (KTD3).
  #
  #   Connectors::Intercom.valid_signature?(request.raw_post, request.headers["X-Hub-Signature"])
  #   Connectors::Intercom.call(notification) # => Items::Ingest::Result or nil when ignored
  #
  # Only customer-authored messages are ingested: the opening message of
  # conversation.user.created and the newest part of conversation.user.replied.
  class Intercom
    CREATED = "conversation.user.created"
    REPLIED = "conversation.user.replied"
    CUSTOMER_AUTHOR_TYPES = %w[user lead contact].freeze
    CATCH_ALL_SELECTOR = "*"
    BLOCK_ELEMENTS = "p, div, li, blockquote, pre, h1, h2, h3, h4, h5, h6, tr"

    def self.valid_signature?(raw_body, header, secret: ENV["INTERCOM_CLIENT_SECRET"])
      return false if secret.blank? || header.blank?

      expected = "sha1=#{OpenSSL::HMAC.hexdigest("SHA1", secret, raw_body.to_s)}"
      ActiveSupport::SecurityUtils.secure_compare(expected, header.to_s)
    end

    def self.call(notification)
      new(notification).call
    end

    def self.plain_text(html)
      fragment = Nokogiri::HTML5.fragment(html.to_s)
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css(BLOCK_ELEMENTS).each { |node| node.add_next_sibling("\n") }
      fragment.text.gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
    end

    def initialize(notification)
      @notification = notification.is_a?(Hash) ? notification : {}
      @conversation = @notification.dig("data", "item") || {}
    end

    def call
      part = customer_part
      return if part.nil? || @conversation["id"].blank?

      inbound = inbound_message(part)
      return if inbound.body.blank?

      source = source_for_conversation
      return if source.nil?

      begin
        Items::Ingest.call(source: source, inbound: inbound)
      rescue ActiveModel::ValidationError => error
        source.record_error!("Intercom: #{error.message}")
        nil
      end
    end

    private

    def topic
      @notification["topic"]
    end

    def customer_part
      part =
        case topic
        when CREATED then @conversation["source"]
        when REPLIED then Array(@conversation.dig("conversation_parts", "conversation_parts")).last
        end
      return unless part.is_a?(Hash)
      return if topic == REPLIED && part["part_type"] != "comment"

      part if CUSTOMER_AUTHOR_TYPES.include?(part.dig("author", "type"))
    end

    def inbound_message(part)
      author = part["author"] || {}
      conversation_id = @conversation["id"].to_s

      Items::InboundMessage.new(
        external_id: part["id"].to_s.presence,
        thread_key: conversation_id,
        body: self.class.plain_text(part["body"]),
        occurred_at: timestamp(part["created_at"] || @conversation["created_at"]),
        author_name: author["name"].presence,
        author_email: author["email"].presence,
        permalink: permalink(conversation_id),
        raw_payload: { "topic" => topic, "conversation_id" => conversation_id, "part" => part }
      )
    end

    def timestamp(value)
      Time.zone.at(Integer(value)) if value.present?
    rescue ArgumentError, TypeError
      nil
    end

    def permalink(conversation_id)
      app_id = @notification["app_id"].presence
      "https://app.intercom.com/a/inbox/#{app_id}/inbox/conversation/#{conversation_id}" if app_id
    end

    # A conversation already on an item keeps flowing to that item's source
    # after it is reassigned to a team no source selects (KTD2).
    def source_for_conversation
      sources = Source.intercom.active
      team_id = @conversation["team_assignee_id"].to_s.presence

      (team_id && sources.find_by(selector: team_id)) ||
        existing_item_source(sources) ||
        sources.find_by(selector: CATCH_ALL_SELECTOR)
    end

    def existing_item_source(sources)
      source_id = Item.where(source_kind: Source.kinds[:intercom], thread_key: @conversation["id"].to_s).pick(:source_id)
      sources.find_by(id: source_id) if source_id
    end
  end
end
