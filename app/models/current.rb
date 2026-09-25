class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # Set while backfilled history or a rerun is written, so dashboards throttle
  # the pings it causes (MoodChannel.refresh).
  attribute :backfill
  delegate :user, to: :session, allow_nil: true
end
