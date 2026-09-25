class Setting < ApplicationRecord
  # Who counts as Every's own team (Messages::AuthorRole). Forms send each list
  # as one string of comma- or space-separated values.
  LIST = ->(value) { (value.is_a?(String) ? value.split(/[\s,]+/) : Array(value)).map { |entry| entry.to_s.strip } }
  normalizes :team_email_domains,
    with: ->(value) { LIST.call(value).map { |domain| domain.downcase.delete_prefix("@") }.compact_blank.uniq }
  normalizes :team_discord_role_ids, :team_discord_user_ids, with: ->(value) { LIST.call(value).compact_blank.uniq }
  normalizes :slack_channel_id, with: ->(value) { value.strip.presence }
  normalizes :digest_time_zone, with: ->(value) { value.strip }

  validates :slack_channel_id, format: { with: /\A[CG][A-Z0-9]{6,}\z/, message: "must be a Slack channel ID like C0AGB2RKA6R" },
    allow_nil: true
  validates :digest_hour, numericality: { only_integer: true, in: 0..23 }
  validate :digest_time_zone_exists

  validates :low_confidence_threshold, :escalation_threshold,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :report_back_window_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :anomaly_sensitivity, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  validates :anomaly_min_count, :anomaly_min_baseline_windows, :anomaly_active_days,
    numericality: { only_integer: true, greater_than: 0 }

  def self.current
    first || create!
  end

  def report_back_window
    report_back_window_minutes.minutes
  end

  # The channel for the daily overview, negative anomaly alerts, and escalations
  # of products without a channel of their own.
  def slack_channel?
    slack_channel_id.present?
  end

  def digest_zone
    ActiveSupport::TimeZone[digest_time_zone]
  end

  private

  def digest_time_zone_exists
    errors.add(:digest_time_zone, "is not a known time zone") if digest_zone.nil?
  end
end
