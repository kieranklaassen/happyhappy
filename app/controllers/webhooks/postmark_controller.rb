module Webhooks
  # Postmark inbound email webhook. Postmark sends the credentials as HTTP basic
  # auth embedded in the webhook URL and retries any non-200 response, so an
  # unknown recipient still answers 200.
  class PostmarkController < ActionController::Base
    skip_forgery_protection
    before_action :authenticate

    def create
      payload = JSON.parse(request.raw_post)
      return head :bad_request unless payload.is_a?(Hash)

      Connectors::Postmark.call(payload)
      head :ok
    rescue JSON::ParserError
      head :bad_request
    rescue ActiveModel::ValidationError
      head :unprocessable_content
    end

    private

    def authenticate
      user = ENV["POSTMARK_INBOUND_USER"].to_s
      password = ENV["POSTMARK_INBOUND_PASSWORD"].to_s

      authenticate_or_request_with_http_basic("Postmark") do |given_user, given_password|
        next false if user.empty? || password.empty?

        ActiveSupport::SecurityUtils.secure_compare(given_user, user) &
          ActiveSupport::SecurityUtils.secure_compare(given_password, password)
      end
    end
  end
end
