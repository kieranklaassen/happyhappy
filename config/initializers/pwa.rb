# frozen_string_literal: true

# PWA identity — the ONE place to rename or re-brand the installable app.
#
# Read by app/views/pwa/manifest.json.erb (web app manifest) and by
# app/views/layouts/application.html.erb (<title> fallback, description,
# application-name, theme-color, and link-preview metas), so the browser, the home-screen icon, and the page header
# always agree. Downstream apps edit these values and nothing else.
Rails.application.config.x.pwa.name = "happyhappy"
Rails.application.config.x.pwa.short_name = "happyhappy"
Rails.application.config.x.pwa.title = "happyhappy: how your customers feel"
Rails.application.config.x.pwa.description = "A clear read on how your customers feel across Slack, Discord, " \
  "Intercom, email, and X, handled by your agents."
Rails.application.config.x.pwa.theme_color = "#FBF7EF"
Rails.application.config.x.pwa.background_color = "#FBF7EF"

# Link previews need absolute URLs, and crawlers only ever see production.
Rails.application.config.x.pwa.site_url = "https://happyhappy.every.to"
Rails.application.config.x.pwa.og_image = "/og-image.png"
