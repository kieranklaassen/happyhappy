module Slack
  # Block Kit payload for one escalation: quote, product, source, customer handle, and item link (R29).
  class EscalationMessage
    include Formatting

    def initialize(escalation)
      @escalation = escalation
      @item = escalation.item
      @message = escalation.message || @item.messages.last
    end

    def to_h
      { text: escape(text), blocks: blocks }
    end

    private

    def text
      "Angry #{@escalation.product.name} customer #{customer_handle(@item)} on #{@item.source.name}"
    end

    def blocks
      [
        section(":rotating_light: *#{escape(text)}*"),
        section(quote(@message&.body, limit: SECTION_LIMIT - 10)),
        section(fields_text),
        context(links_text)
      ]
    end

    def fields_text
      [
        "*Product:* #{escape(@escalation.product.name)}",
        "*Source:* #{escape(@item.source.name)}",
        "*Customer:* #{escape(customer_handle(@item))}",
        "*Anger:* #{percent(@item.anger_probability)}"
      ].join("\n")
    end

    def links_text
      links = [ link(item_url(@item), "Open in happyhappy") ]
      links << link(@item.permalink, "View original") if @item.permalink.present?
      links.join("  |  ")
    end
  end
end
