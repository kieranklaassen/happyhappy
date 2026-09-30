# frozen_string_literal: true

# Development-only look at an incident's Slack ping without a Slack workspace: renders the Block
# Kit from Slack::IncidentMessage to static HTML that approximates Slack's layout. Run `mood:demo`
# first for a Cora incident to preview.
module IncidentPreview
  module_function

  EMOJI = { "rotating_light" => "🚨", "white_check_mark" => "✅", "warning" => "⚠️" }.freeze
  PREVIEW_MENTIONS = %w[U0AGQDHRV8U S0BINGSU01].freeze

  def page(variants)
    <<~HTML
      <!doctype html>
      <html><head><meta charset="utf-8"><title>Incident ping preview</title><style>#{CSS}</style></head>
      <body>#{variants.map { |title, payload| message(title, payload) }.join}</body></html>
    HTML
  end

  def message(title, payload)
    <<~HTML
      <section class="variant"><h2>#{ERB::Util.h(title)}</h2>
        <div class="msg"><div class="avatar">☀</div><div class="body">
          <div class="meta"><b>happyhappy</b><span class="app">APP</span></div>
          #{payload[:blocks].map { |block| block(block) }.join}
        </div></div>
        <p class="fallback">Notification text: #{ERB::Util.h(payload[:text])}</p>
      </section>
    HTML
  end

  def block(block)
    case block[:type]
    when "section" then %(<div class="section">#{mrkdwn(block.dig(:text, :text))}</div>)
    when "context" then %(<div class="context">#{block[:elements].map { |element| mrkdwn(element[:text]) }.join(" ")}</div>)
    when "actions" then %(<div class="actions">#{block[:elements].map { |element| button(element) }.join}</div>)
    else ""
    end
  end

  def button(element)
    label = ERB::Util.h(element.dig(:text, :text))
    kind = element[:url] ? "link to #{element[:url]}" : "action #{element[:action_id]}"
    %(<span class="button #{element[:style]}" title="#{ERB::Util.h(kind)}">#{label}</span>)
  end

  # Slack escapes &, <, and > exactly like HTML, so escaped text drops straight into the page;
  # only Slack's own <...> control sequences and markup need converting.
  def mrkdwn(text)
    lines = text.to_s.split("\n").map do |line|
      quoted = line.start_with?("&gt; ")
      line = line.delete_prefix("&gt; ") if quoted
      line = line.gsub(/<@([UW][A-Z0-9]+)>/) { %(<span class="mention">@#{$1}</span>) }
        .gsub(/<!subteam\^([A-Z0-9]+)>/) { %(<span class="mention">@on-call group #{$1}</span>) }
        .gsub(/<([^|<>]+)\|([^<>]+)>/) { %(<a href="#{$1}">#{$2}</a>) }
        .gsub(/(?<![\w*])\*([^*\n]+)\*(?![\w*])/) { "<b>#{$1}</b>" }
        .gsub(/(?<!\w)~([^~\n]+)~(?!\w)/) { "<s>#{$1}</s>" }
        .gsub(/:([a-z_]+):/) { EMOJI.fetch($1, ":#{$1}:") }
      quoted ? %(<blockquote>#{line}</blockquote>) : "#{line}<br>"
    end
    lines.join
  end

  CSS = <<~CSS
    body { font: 15px/1.47 -apple-system, "Segoe UI", Lato, sans-serif; color: #1d1c1d; background: #fff; margin: 0; padding: 24px; }
    .variant { max-width: 760px; margin: 0 0 28px; border: 1px solid #e8e8e8; border-radius: 8px; padding: 12px 16px; }
    h2 { font-size: 12px; text-transform: uppercase; letter-spacing: .06em; color: #616061; margin: 0 0 10px; }
    .msg { display: flex; gap: 8px; }
    .avatar { width: 36px; height: 36px; border-radius: 6px; background: #f8d774; display: grid; place-items: center; font-size: 22px; flex: none; }
    .meta { display: flex; gap: 6px; align-items: baseline; }
    .app { font-size: 10px; background: #e8e8e8; color: #616061; border-radius: 3px; padding: 0 3px; }
    .section { margin: 4px 0 8px; }
    .context { font-size: 12px; color: #616061; margin-top: 6px; }
    a { color: #1264a3; text-decoration: none; }
    .mention { background: #fff3c4; color: #1264a3; border-radius: 3px; padding: 0 2px; }
    blockquote { margin: 2px 0 6px; padding-left: 10px; border-left: 4px solid #ddd; color: #1d1c1d; }
    .actions { display: flex; gap: 8px; margin: 6px 0; }
    .button { border: 1px solid #bbb; border-radius: 4px; padding: 3px 12px; font-size: 13px; font-weight: 700; }
    .button.primary { background: #007a5a; border-color: #007a5a; color: #fff; }
    .fallback { font-size: 12px; color: #868686; margin: 8px 0 0 44px; }
  CSS
end

namespace :incidents do
  desc "Render the latest incident's Slack ping to tmp/incident_slack_preview.html (development only)"
  task preview: :environment do
    abort "incidents:preview only runs in development" unless Rails.env.development?

    incident = Incident.includes(:product).recent_first.first or abort "No incidents yet. Run bin/rails mood:demo first."
    incident.product.alert_mention_ids = IncidentPreview::PREVIEW_MENTIONS
    incident.status = "open"
    variants = [
      [ "New incident (Slack interactivity on: Mark resolved is an action button)",
        Slack::IncidentMessage.new(incident, interactive: true).to_h ],
      [ "Same ping with interactivity off (Mark resolved links to the incident page)",
        Slack::IncidentMessage.new(incident, interactive: false).to_h ]
    ]
    # In memory only: the preview never saves.
    incident.assign_attributes(status: "resolved", resolved_at: Time.current, resolved_by_name: "Ana Every",
      resolution_note: "Rolled back the IMAP sync change; support is caught up.")
    variants << [ "After resolve (chat.update of the same message)", Slack::IncidentMessage.new(incident).to_h ]
    path = Rails.root.join("tmp/incident_slack_preview.html")
    File.write(path, IncidentPreview.page(variants))
    puts "Wrote #{path}"
  end
end
