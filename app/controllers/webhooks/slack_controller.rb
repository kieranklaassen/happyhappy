module Webhooks
  # Slack Events API request URL. Authenticated by the v0 request signature
  # only; acks within Slack's three-second window and leaves Slack API lookups
  # to SlackEventJob. Retries carry the same event and dedupe on ingest.
  class SlackController < ActionController::Base
    skip_forgery_protection

    rescue_from Slack::Events::Request::MissingSigningSecret, Slack::Events::Request::InvalidSignature,
      Slack::Events::Request::TimestampExpired, with: :unauthorized
    rescue_from JSON::ParserError, with: :bad_request

    def create
      verify_signature!
      payload = JSON.parse(request.raw_post)

      case payload["type"]
      when "url_verification"
        render json: { challenge: payload["challenge"] }
      when "event_callback"
        SlackEventJob.perform_later(payload) if Connectors::Slack.ingestible?(payload)
        head :ok
      else
        head :ok
      end
    end

    private

    def verify_signature!
      secret = ENV["SLACK_SIGNING_SECRET"].presence or raise Slack::Events::Request::MissingSigningSecret
      Slack::Events::Request.new(request, signing_secret: secret).verify!
    end

    def unauthorized(error)
      Rails.logger.warn("[slack] rejected event request: #{error.class.name.demodulize}")
      head :unauthorized
    end

    def bad_request
      head :bad_request
    end
  end
end
