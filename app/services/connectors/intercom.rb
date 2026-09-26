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
    # A customer writing into a closed conversation reopens it, and Intercom
    # records that message as an "open" part rather than a "comment".
    CUSTOMER_PART_TYPES = %w[comment open].freeze
    CATCH_ALL_SELECTOR = "*"
    BLOCK_ELEMENTS = "p, div, li, blockquote, pre, h1, h2, h3, h4, h5, h6, tr"

    def self.valid_signature?(raw_body, header, secret: ENV["INTERCOM_CLIENT_SECRET"])
      return false if secret.blank? || header.blank?

      expected = "sha1=#{OpenSSL::HMAC.hexdigest("SHA1", secret, raw_body.to_s)}"
      ActiveSupport::SecurityUtils.secure_compare(expected, header.to_s)
    end

    def self.call(notification, backfill: false)
      result = new(notification, backfill: backfill).call
      conversation = notification.is_a?(Hash) ? notification.dig("data", "item") : nil
      sync_state(conversation) if conversation.is_a?(Hash) && conversation["type"] == "conversation"
      result
    end

    # Mirrors the conversation's Intercom state onto its item. Every conversation
    # webhook carries the state after the change, so a customer reply that
    # reopens it reads open, and an admin close (conversation.admin.closed, the
    # close part of a reply or ticket) reads closed and marks the item handled.
    # A snooze only records the state: someone is waiting on the customer.
    #
    #   Connectors::Intercom.sync_state({ "id" => "215470000000777", "state" => "closed" })
    def self.sync_state(conversation, backfill: false)
      state = conversation["state"].to_s
      return unless Item::EXTERNAL_STATES.include?(state)

      item = Item.find_by(source_kind: Source.kinds[:intercom], thread_key: conversation["id"].to_s)
      apply_state(item, state, backfill: backfill) if item
    end

    # Returns :closed when this closed an unresolved item, :state when only the
    # state changed, or nil when nothing did.
    def self.apply_state(item, state, backfill: false)
      item.with_lock do
        changed = item.external_state != state
        item.update!(external_state: state) if changed
        if state == "closed" && Item::UNRESOLVED_STATUSES.include?(item.status)
          item.change_status!(:handled, reason: "closed_in_intercom", **(backfill ? { backfill: true } : {}))
          next :closed
        end
        :state if changed
      end
    end

    # Ingests every customer-authored message of a conversation fetched from the
    # REST API (GET /conversations/{id}) that was written at or after `since`, by
    # replaying it as the webhook notifications that would have delivered it.
    #
    #   Connectors::Intercom.ingest_conversation(conversation, app_id: "abc123", since: 90.days.ago)
    #   # => [Items::Ingest::Result, ...]
    def self.ingest_conversation(conversation, app_id:, since:, backfill: true)
      parts = Array(conversation.dig("conversation_parts", "conversation_parts"))
      notifications = [ notification(CREATED, conversation, app_id) ] + parts.map do |part|
        notification(REPLIED, conversation.merge("conversation_parts" => { "conversation_parts" => [ part ] }), app_id)
      end

      notifications.filter_map do |notification|
        instance = new(notification, backfill: backfill)
        instance.call if instance.written_since?(since)
      end
    end

    def self.notification(topic, conversation, app_id)
      { "topic" => topic, "app_id" => app_id, "data" => { "item" => conversation } }
    end
    private_class_method :notification

    def self.plain_text(html)
      fragment = Nokogiri::HTML5.fragment(html.to_s)
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css(BLOCK_ELEMENTS).each { |node| node.add_next_sibling("\n") }
      fragment.text.gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
    end

    def initialize(notification, backfill: false)
      @notification = notification.is_a?(Hash) ? notification : {}
      @conversation = @notification.dig("data", "item") || {}
      @backfill = backfill
    end

    def written_since?(time)
      written_at = timestamp(customer_part&.dig("created_at") || @conversation["created_at"])
      written_at.present? && written_at >= time
    end

    def call
      part = customer_part
      return if part.nil? || @conversation["id"].blank?

      inbound = inbound_message(part)
      return if inbound.body.blank?

      source = source_for_conversation
      return if source.nil?

      begin
        Items::Ingest.call(source: source, inbound: inbound, backfill: @backfill)
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
      return if topic == REPLIED && !CUSTOMER_PART_TYPES.include?(part["part_type"])

      part if CUSTOMER_AUTHOR_TYPES.include?(part.dig("author", "type"))
    end

    def inbound_message(part)
      author = part["author"] || {}
      conversation_id = @conversation["id"].to_s
      body = self.class.plain_text(part["body"])

      Items::InboundMessage.new(
        external_id: part["id"].to_s.presence,
        thread_key: conversation_id,
        body: body,
        occurred_at: timestamp(part["created_at"] || @conversation["created_at"]),
        author_name: author["name"].presence,
        # A lead Fin has not identified yet has no email until they type it in.
        author_email: author["email"].presence || typed_email(body),
        permalink: permalink(conversation_id),
        raw_payload: { "topic" => topic, "conversation_id" => conversation_id, "part" => part }
      )
    end

    def typed_email(body)
      body.strip.delete_prefix("mailto:") if body.match?(Message::EMAIL_ONLY)
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
    # after it is reassigned to a team no source selects (KTD2). Matching
    # ignores status so a paused source stops its own conversations instead of
    # letting them fall through to the catch-all.
    def source_for_conversation
      sources = Source.intercom
      team_id = @conversation["team_assignee_id"].to_s.presence

      source = (team_id && sources.find_by(selector: team_id)) ||
        existing_item_source(sources) ||
        sources.find_by(selector: CATCH_ALL_SELECTOR)

      source if source&.active?
    end

    def existing_item_source(sources)
      source_id = Item.where(source_kind: Source.kinds[:intercom], thread_key: @conversation["id"].to_s).pick(:source_id)
      sources.find_by(id: source_id) if source_id
    end
  end
end
