# frozen_string_literal: true

# Tells open dashboards that the crowd changed. The ping carries no customer
# data; the page reloads its own props through Inertia.
class MoodChannel < ApplicationCable::Channel
  STREAM = "mood"

  # Runs after an item commits, so a cable failure must not fail the ingest or
  # classification that triggered it; dashboards still catch up by polling.
  def self.refresh
    ActionCable.server.broadcast(STREAM, { changed_at: Time.current.iso8601 })
  rescue StandardError => error
    Rails.error.report(error, handled: true)
  end

  def subscribed
    stream_from STREAM
  end
end
