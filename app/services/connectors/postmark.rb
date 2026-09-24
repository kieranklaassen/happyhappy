module Connectors
  # Maps one Postmark inbound webhook payload onto the email source it was sent
  # to and ingests it. Returns nil when no email source matches a recipient.
  #
  #   Connectors::Postmark.call(payload) # => Items::Ingest::Result or nil
  #
  # Raises ActiveModel::ValidationError for a payload that cannot be ingested,
  # after recording the error on the matched source.
  class Postmark
    MESSAGE_ID = /<([^<>\s]+)>/
    SUBJECT_PREFIX = /\A\s*((re|fw|fwd|aw|sv)\s*(\[\d+\])?\s*:\s*)+/i

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = payload
    end

    def call
      source = find_source or return
      Items::Ingest.call(source: source, inbound: inbound_message)
    rescue ActiveModel::ValidationError => error
      source.record_error!(error)
      raise
    end

    private

    attr_reader :payload

    # Addresses match case-insensitively: senders and forwarders change the
    # case of an address freely, and no mail provider in use treats it as
    # significant.
    def find_source
      recipients.each do |address|
        source = Source.email.find_by("LOWER(selector) = ?", address)
        return source if source
      end
      nil
    end

    def recipients
      addresses = [ payload["OriginalRecipient"] ]
      %w[ToFull CcFull BccFull].each do |field|
        addresses.concat(Array(payload[field]).map { |recipient| recipient["Email"] })
      end
      addresses.filter_map { |address| address.to_s.strip.downcase.presence }.uniq
    end

    def inbound_message
      Items::InboundMessage.new(
        external_id: payload["MessageID"],
        thread_key: thread_key,
        body: body,
        occurred_at: occurred_at,
        author_handle: sender_email,
        author_name: payload.dig("FromFull", "Name").presence || payload["FromName"].presence,
        author_email: sender_email,
        raw_payload: raw_payload
      )
    end

    # The thread's root Message-ID: the first References id, else In-Reply-To,
    # else this mail's own Message-ID. Postmark's top-level MessageID is its own
    # delivery id and never appears in a reply's headers.
    def thread_key
      root = message_ids("References").first || message_ids("In-Reply-To").first || message_ids("Message-ID").first
      return root if root

      subject = payload["Subject"].to_s.sub(SUBJECT_PREFIX, "").squish.downcase
      "#{sender_email}|#{subject}" if sender_email
    end

    def message_ids(name)
      value = headers[name.downcase].to_s
      ids = value.scan(MESSAGE_ID).flatten
      ids.presence || value.split.first(1)
    end

    def headers
      @headers ||= Array(payload["Headers"]).each_with_object({}) do |header, found|
        found[header["Name"].to_s.downcase] ||= header["Value"]
      end
    end

    def body
      payload["StrippedTextReply"].presence ||
        payload["TextBody"].presence ||
        Loofah.html5_fragment(payload["HtmlBody"].to_s).to_text(encode_special_chars: false).strip
    end

    def occurred_at
      Time.zone.parse(payload["Date"].to_s)
    rescue ArgumentError
      nil
    end

    def sender_email
      (payload.dig("FromFull", "Email").presence || payload["From"]).to_s.strip.downcase.presence
    end

    def raw_payload
      payload.merge("Attachments" => Array(payload["Attachments"]).map { |attachment| attachment.except("Content") })
    end
  end
end
