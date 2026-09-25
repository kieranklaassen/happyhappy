require "net/http"

class WebhookDelivery < ApplicationRecord
  MAX_ATTEMPTS = 8
  TIMEOUT = 10.seconds
  RETENTION = 30.days
  ERROR_BODY_LIMIT = 500

  enum :status, { pending: "pending", succeeded: "succeeded", failed: "failed" }, validate: true

  belongs_to :webhook_endpoint
  belongs_to :item_event, optional: true

  validates :event, inclusion: { in: WebhookEndpoint::EVENTS + [ Webhooks::Payload::TEST_EVENT ] }

  scope :expired, -> { where(created_at: ...RETENTION.ago) }

  # One signed POST. Records the outcome and returns true on a 2xx response.
  # Any failure to get a response (DNS, TLS, timeout, malformed reply) counts
  # as a failed attempt so the delivery keeps retrying instead of sticking.
  def attempt!(now: Time.current)
    response_code, error = send_signed(now)
    update!(attempts: attempts + 1, last_attempted_at: now, response_code: response_code,
      status: error ? status : :succeeded, last_error: error&.truncate(ERROR_BODY_LIMIT))
    error.nil?
  end

  def exhausted?
    attempts >= MAX_ATTEMPTS
  end

  private

  # Returns [response code, error message or nil].
  def send_signed(now)
    response = post(payload.to_json, now)
    code = response.code.to_i
    [ code, ("HTTP #{code}: #{error_body(response)}" unless code.between?(200, 299)) ]
  rescue StandardError => error
    [ nil, "#{error.class}: #{error.message}" ]
  end

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
