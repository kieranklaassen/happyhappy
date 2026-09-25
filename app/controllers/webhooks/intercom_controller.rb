module Webhooks
  # Intercom notification endpoint (KTD5): outside the session gate, authenticated
  # by X-Hub-Signature. Intercom resends anything not answered 200 within five
  # seconds; message-level dedupe in Items::Ingest absorbs the resend.
  class IntercomController < ActionController::Base
    skip_forgery_protection

    # Intercom sends HEAD to validate the URL when the webhook is saved.
    def validate
      head :ok
    end

    def create
      unless Connectors::Intercom.valid_signature?(request.raw_post, request.headers["X-Hub-Signature"])
        return head :unauthorized
      end

      Connectors::Intercom.call(JSON.parse(request.raw_post))
      head :ok
    rescue JSON::ParserError
      head :bad_request
    end
  end
end
