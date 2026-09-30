module Slack
  # Block Kit payload for an incident ping in the product's alert channel: who is on call, what
  # spiked (expected against actual), which sources, a few customers behind it, and buttons to open
  # or resolve the incident. Once resolved it says who resolved it and drops the buttons and mentions.
  #
  #   Slack::IncidentMessage.new(incident).to_h # => { text:, blocks: }
  #
  # "Mark resolved" is an interactive button when Settings has Slack interactivity on (Slack sends the
  # click to /webhooks/slack/interactions); otherwise it links to the incident page, because a Slack
  # button cannot carry both a url and an action.
  class IncidentMessage
    include Formatting
    include AnomalyWording

    RESOLVE_ACTION = "incident_resolve".freeze
    ANOMALY_COUNT = 6
    EXAMPLE_COUNT = 3

    def initialize(incident, interactive: Setting.current.slack_interactivity)
      @incident = incident
      @product = incident.product
      @interactive = interactive
    end

    def to_h
      { text: fallback_text, blocks: blocks }
    end

    private

    def blocks
      [
        section(headline),
        section("*What spiked*\n#{anomalies_text}"),
        (section("*Sources*\n#{sources.map { |source| escape(source.name) }.join(", ")}") if sources.any?),
        (section("*Customers behind it*\n#{examples_text}") if examples.any?),
        (actions if @incident.open?),
        context(context_text)
      ].compact
    end

    def fallback_text
      if @incident.resolved?
        "Resolved: #{@product.name} incident (#{lead.label.to_s.downcase_first} spiked)"
      else
        [ "#{@product.name} incident: #{lead.label.to_s.downcase_first} spiked", mentions ].compact_blank.join(" ")
      end
    end

    def headline
      title = ":rotating_light: *#{escape(@product.name)} incident*: #{escape(lead.label.to_s.downcase_first)} spiked"
      if @incident.resolved?
        resolved = ":white_check_mark: *Resolved* by #{escape(@incident.resolved_by_name || "someone")}"
        resolved += ": #{escape(@incident.resolution_note.squish.truncate(QUOTE_LIMIT))}" if @incident.resolution_note.present?
        "~#{title.delete_prefix(":rotating_light: ")}~\n#{resolved}"
      else
        [ title, mentions ].compact_blank.join("\n")
      end
    end

    def mentions
      Mentions.render(@product.alert_mention_ids)
    end

    def anomalies
      @anomalies ||= @incident.anomalies.includes(:source)
        .sort_by { |anomaly| [ anomaly.source_id ? 1 : 0, -anomaly.strength, -anomaly.z_score ] }
    end

    def lead
      anomalies.first
    end

    def anomalies_text
      lines = anomalies.first(ANOMALY_COUNT).map do |anomaly|
        where = anomaly.source ? " on #{escape(anomaly.source.name)}" : " across all sources"
        "• #{escape(anomaly.label)}#{where}: #{anomaly_value(anomaly, anomaly.actual)} vs about " \
          "#{anomaly_value(anomaly, anomaly.expected)} expected (#{anomaly.severity})"
      end
      extra = anomalies.size - ANOMALY_COUNT
      lines << "…and #{extra} more" if extra.positive?
      lines.join("\n")
    end

    def sources
      @sources ||= @incident.sources
    end

    def examples
      @examples ||= Item.where(id: @incident.item_ids).by_actionability.includes(:source).limit(EXAMPLE_COUNT).to_a
    end

    def examples_text
      examples.map do |item|
        body = Message.quotable(item.messages.from_customers)&.body
        "#{link(item_url(item), customer_handle(item))} · #{escape(item.source.name)}\n#{quote(body)}"
      end.join("\n")
    end

    def actions
      {
        type: "actions",
        elements: [
          { type: "button", text: plain("Open incident"), url: @incident.url },
          resolve_button
        ]
      }
    end

    def resolve_button
      button = { type: "button", text: plain("Mark resolved"), style: "primary" }
      if @interactive
        button.merge(action_id: RESOLVE_ACTION, value: @incident.id.to_s,
          confirm: { title: plain("Resolve this incident?"), text: plain("This stops alerts about these spikes."),
            confirm: plain("Resolve"), deny: plain("Cancel") })
      else
        button.merge(url: "#{@incident.url}#resolve")
      end
    end

    def context_text
      zone = Setting.current.digest_zone
      opened = @incident.opened_at.in_time_zone(zone).strftime("%b %-d %H:%M %Z")
      parts = [ "Opened #{opened}", "#{anomalies.size} #{"anomaly".pluralize(anomalies.size)}" ]
      parts << "resolved #{@incident.resolved_at.in_time_zone(zone).strftime("%b %-d %H:%M %Z")}" if @incident.resolved?
      parts.join(" · ")
    end

    def plain(text)
      { type: "plain_text", text: text }
    end
  end
end
