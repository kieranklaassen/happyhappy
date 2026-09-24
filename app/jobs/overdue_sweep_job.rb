# Flags claimed and in-progress items whose agent has gone quiet for longer than
# the report-back window, measured from the later of claimed_at and last_reported_at.
# Runs every 5 minutes from config/recurring.yml.
class OverdueSweepJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = Setting.current.report_back_window.ago
    quiet_since(cutoff).find_each { |item| flag(item, cutoff) }
  end

  private

  def quiet_since(cutoff)
    Item.where(status: %w[claimed in_progress], overdue: false)
      .where.not(claimed_by_agent_id: nil)
      .where(claimed_at: ...cutoff)
      .where("items.last_reported_at IS NULL OR items.last_reported_at < ?", cutoff)
  end

  # Re-checks the condition in the UPDATE so a report or release that lands
  # between the scan and the flag is never marked overdue.
  def flag(item, cutoff)
    Item.transaction do
      flagged = quiet_since(cutoff).where(id: item.id).update_all(overdue: true, updated_at: Time.current)
      next unless flagged == 1

      item.record_event!(:overdue, agent_id: item.claimed_by_agent_id,
        quiet_since: [ item.claimed_at, item.last_reported_at ].compact.max.iso8601)
    end
  end
end
