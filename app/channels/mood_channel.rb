# frozen_string_literal: true

# Tells open dashboards that the crowd changed. The ping carries no customer
# data; the page reloads its own props through Inertia.
class MoodChannel < ApplicationCable::Channel
  STREAM = "mood"

  def self.refresh
    ActionCable.server.broadcast(STREAM, { changed_at: Time.current.iso8601 })
  end

  def subscribed
    stream_from STREAM
  end
end
