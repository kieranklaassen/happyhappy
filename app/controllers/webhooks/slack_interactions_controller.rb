module Webhooks
  # Slack interactivity Request URL (Settings "Slack interactivity" must be on for incident pings to
  # carry an action button). Authenticated by the v0 request signature only; acks within Slack's
  # three-second window and leaves the users.info lookup and the resolve to ResolveIncidentFromSlackJob.
  class SlackInteractionsController < ActionController::Base
    skip_forgery_protection

    rescue_from Slack::Events::Request::MissingSigningSecret, Slack::Events::Request::InvalidSignature,
      Slack::Events::Request::TimestampExpired, with: :unauthorized
    rescue_from JSON::ParserError, with: :bad_request

    def create
      verify_signature!
      payload = JSON.parse(params.require(:payload))

      if payload["type"] == "block_actions"
        payload["actions"].to_a.select { |action| action["action_id"] == Slack::IncidentMessage::RESOLVE_ACTION }.each do |action|
          ResolveIncidentFromSlackJob.perform_later(incident_id: action["value"].to_i, slack_user_id: payload.dig("user", "id"),
            slack_user_name: payload.dig("user", "name") || payload.dig("user", "username"))
        end
      end
      head :ok
    end

    private

    def verify_signature!
      secret = ENV["SLACK_SIGNING_SECRET"].presence or raise Slack::Events::Request::MissingSigningSecret
      Slack::Events::Request.new(request, signing_secret: secret).verify!
    end

    def unauthorized(error)
      Rails.logger.warn("[slack] rejected interaction request: #{error.class.name.demodulize}")
      head :unauthorized
    end

    def bad_request
      head :bad_request
    end
  end
end
