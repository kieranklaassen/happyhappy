# The one daily overview of all products posted to the Settings Slack channel,
# claimed per local day (Setting#digest_time_zone) so a day never gets two.
class OverviewDigest < ApplicationRecord
  validates :date, presence: true, uniqueness: true

  def posted?
    posted_at.present?
  end
end
