# Resolves an incident from its Slack "Mark resolved" button, as the happyhappy user whose email
# matches the Slack user's (users.info, users:read.email), else under the Slack name.
class ResolveIncidentFromSlackJob < ApplicationJob
  queue_as :realtime

  retry_on Slack::Client::RetryableError, wait: :polynomially_longer, attempts: 5

  def perform(incident_id:, slack_user_id:, slack_user_name:)
    incident = Incident.find_by(id: incident_id)
    return if incident.nil? || incident.resolved?

    profile = slack_profile(slack_user_id)
    user = User.find_by(email_address: profile[:email].downcase) if profile[:email].present?
    name = profile[:name].presence || slack_user_name.presence || slack_user_id
    Incidents::Resolve.call(incident: incident, actor: user, actor_name: (name unless user))
  end

  private

  def slack_profile(slack_user_id)
    return {} if slack_user_id.blank?

    info = Slack::Client.new.user_info(user: slack_user_id)
    profile = info["profile"] || {}
    { email: profile["email"], name: profile["real_name"].presence || profile["display_name"].presence || info["name"] }
  rescue Slack::Client::RetryableError
    raise
  rescue Slack::Client::Error => error
    Rails.logger.warn("[slack] users.info failed for an incident resolve: #{error.message}")
    {}
  end
end
