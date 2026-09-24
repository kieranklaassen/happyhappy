module Slack
  module Formatting
    # Block Kit section text is capped at 3000 characters.
    SECTION_LIMIT = 3000
    QUOTE_LIMIT = 500

    private

    def escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def quote(text, limit: QUOTE_LIMIT)
      "&gt; #{escape(text.to_s.squish.truncate(limit))}"
    end

    def link(url, label)
      "<#{url}|#{escape(label)}>"
    end

    def item_url(item)
      "#{ENV.fetch("PUBLIC_BASE_URL", "http://localhost:3000").chomp("/")}/items/#{item.id}"
    end

    def customer_handle(item)
      item.author_handle.presence || item.author_email.presence || item.author_name.presence || "unknown customer"
    end

    def percent(probability)
      "#{(probability.to_f * 100).round}%"
    end

    def section(text)
      { type: "section", text: { type: "mrkdwn", text: text.truncate(SECTION_LIMIT) } }
    end

    def context(text)
      { type: "context", elements: [ { type: "mrkdwn", text: text.truncate(SECTION_LIMIT) } ] }
    end
  end
end
