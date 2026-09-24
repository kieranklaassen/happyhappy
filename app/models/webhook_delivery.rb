require "net/http"

class WebhookDelivery < ApplicationRecord
  MAX_ATTEMPTS = 8
  TIMEOUT = 10.seconds
  RETENTION = 30.days
  ERROR_BODY_LIMIT = 500
  NETWORK_ERRORS = [ Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
    Errno::ENETUNREACH, SocketError, OpenSSL::SSL::SSLError, EOFError, IOError ].freeze

  enum :status, { pending: "pending", succeeded: "succeeded", failed: "failed" }, validate: true

  belongs_to :webhook_endpoint
  belongs_to :item_event, optional: true

  validates :event, inclusion: { in: WebhookEndpoint::EVENTS + [ "webhook.test" ] }

  scope :expired, -> { where(created_at: ...RETENTION.ago) }

  # One signed POST. Records the outcome and returns true on a 2xx response.
  def attempt!(now: Time.current)
    body = payload.to_json
    response = post(body, now)
    code = response.code.to_i
    success = code.between?(200, 299)
    update!(attempts: attempts + 1, last_attempted_at: now, response_code: code,
      status: success ? :succeeded : status, last_error: success ? nil : "HTTP #{code}: #{error_body(response)}")
    success
  rescue *NETWORK_ERRORS, URI::InvalidURIError => error
    update!(attempts: attempts + 1, last_attempted_at: now, response_code: nil,
      last_error: "#{error.class}: #{error.message}".truncate(ERROR_BODY_LIMIT))
    false
  end

  def exhausted?
    attempts >= MAX_ATTEMPTS
  end

  private

  def post(body, now)
    uri = URI.parse(webhook_endpoint.url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT
    http.write_timeout = TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json; charset=utf-8"
    request["User-Agent"] = "happyhappy-webhooks"
    request["X-Happyhappy-Event"] = event
    request["X-Happyhappy-Delivery"] = id.to_s
    request[Webhooks::Signature::HEADER] = Webhooks::Signature.sign(webhook_endpoint.secret, body, time: now)
    request.body = body
    http.request(request)
  end

  def error_body(response)
    response.body.to_s.dup.force_encoding(Encoding::UTF_8).scrub.squish.truncate(ERROR_BODY_LIMIT).presence || response.message.to_s
  end
end
