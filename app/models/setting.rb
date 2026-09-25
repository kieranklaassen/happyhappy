class Setting < ApplicationRecord
  # Who counts as Every's own team (Messages::AuthorRole). Forms send each list
  # as one string of comma- or space-separated values.
  LIST = ->(value) { (value.is_a?(String) ? value.split(/[\s,]+/) : Array(value)).map { |entry| entry.to_s.strip } }
  normalizes :team_email_domains,
    with: ->(value) { LIST.call(value).map { |domain| domain.downcase.delete_prefix("@") }.compact_blank.uniq }
  normalizes :team_discord_role_ids, :team_discord_user_ids, with: ->(value) { LIST.call(value).compact_blank.uniq }

  validates :low_confidence_threshold, :escalation_threshold,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :report_back_window_minutes, numericality: { only_integer: true, greater_than: 0 }

  def self.current
    first || create!
  end

  def report_back_window
    report_back_window_minutes.minutes
  end
end
