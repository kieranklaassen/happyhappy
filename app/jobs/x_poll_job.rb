class XPollJob < ApplicationJob
  # Overlapping runs would read and bill the same posts twice.
  limits_concurrency to: 1, key: "x_poll", duration: 15.minutes, on_conflict: :discard

  def perform
    Source.x.where(status: %i[active paused_for_budget]).find_each do |source|
      Connectors::X.poll(source)
    rescue StandardError => error
      source.record_error!(error)
      Rails.error.report(error, context: { source_id: source.id })
    end
  end
end
