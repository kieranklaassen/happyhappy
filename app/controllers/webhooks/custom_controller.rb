module Webhooks
  # Custom inbound webhook (R36 to R38): outside the session gate, addressed by
  # the source's public token and authenticated by X-Happyhappy-Signature
  # (KTD5, KTD17). See docs/custom-webhooks.md for the contract.
  class CustomController < ActionController::Base
    SYNC_RATE_LIMIT = 60
    # One Puma worker (config/deploy.yml), so a process-local store sees every request.
    SYNC_RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

    skip_forgery_protection
    wrap_parameters false

    before_action :set_source
    before_action :reject_oversized_body
    before_action :verify_signature
    rate_limit to: SYNC_RATE_LIMIT, within: 1.minute, by: -> { @source.id }, store: SYNC_RATE_LIMIT_STORE,
      with: -> { render_error "sync rate limit exceeded", :too_many_requests }, if: :sync?

    def create
      result = Connectors::Custom.call(source: @source, raw_body: request.raw_post, sync: sync?)
      render json: result.to_h, status: sync? ? :ok : :accepted
    rescue Connectors::Custom::InvalidPayload => error
      render_error error.message, :unprocessable_content
    end

    private

    # Path and query only: the body is never parsed into params, so malformed
    # JSON reaches the connector and a body key cannot switch on sync mode.
    def set_source
      @source = Source.custom.active.find_by(public_token: request.path_parameters[:token].to_s)
      render_error "unknown webhook", :not_found unless @source
    end

    def reject_oversized_body
      too_large = request.content_length.to_i > Connectors::Custom::MAX_BODY_BYTES ||
        request.raw_post.to_s.bytesize > Connectors::Custom::MAX_BODY_BYTES
      render_error "body over #{Connectors::Custom::MAX_BODY_BYTES} bytes", :content_too_large if too_large
    end

    def verify_signature
      return if Webhooks::Signature.verify(@source.signing_secret, request.raw_post, request.headers[Webhooks::Signature::HEADER])

      render_error "invalid or expired signature", :unauthorized
    end

    def sync?
      ActiveModel::Type::Boolean.new.cast(request.query_parameters["sync"]) == true
    end

    def render_error(message, status)
      render json: { error: message }, status: status
    end
  end
end
