# frozen_string_literal: true

# Tells open dashboards and feeds that items changed. The ping carries no
# customer data; the page reloads its own props through Inertia. Pings caused
# by backfilled history or a rerun say so, and pages space those reloads out.
class MoodChannel < ApplicationCable::Channel
  STREAM = "mood"

  # Runs after an item commits, so a cable failure must not fail the ingest or
  # classification that triggered it; dashboards still catch up by polling.
  def self.refresh
    ActionCable.server.broadcast(STREAM, { changed_at: Time.current.iso8601, backfill: Current.backfill == true })
  rescue StandardError => error
    Rails.error.report(error, handled: true)
  end

  def subscribed
    stream_from STREAM
  end
end
