module Webhooks
  # The one signing scheme for inbound and outbound webhooks (KTD17):
  #
  #   X-Happyhappy-Signature: t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<raw body>">
  #
  #   header = Webhooks::Signature.sign(secret, body, time: Time.current)
  #   Webhooks::Signature.verify(secret, body, header) # => true or false
  #
  # verify accepts any v1 value in the header, so a sender can sign with an old
  # and a new secret while it rotates.
  module Signature
    HEADER = "X-Happyhappy-Signature"
    TOLERANCE = 300

    def self.sign(secret, body, time: Time.current)
      timestamp = time.to_i
      "t=#{timestamp},v1=#{digest(secret, timestamp, body)}"
    end

    def self.verify(secret, body, header, tolerance: TOLERANCE, now: Time.current)
      return false if secret.blank? || header.blank?

      parts = header.to_s.split(",").filter_map { |part| part.strip.split("=", 2) if part.include?("=") }
      timestamp = parts.find { |key, _| key == "t" }&.last
      return false unless timestamp&.match?(/\A\d+\z/)
      return false if (now.to_i - timestamp.to_i).abs > tolerance

      expected = digest(secret, timestamp, body)
      parts.any? { |key, value| key == "v1" && ActiveSupport::SecurityUtils.secure_compare(expected, value) }
    end

    def self.digest(secret, timestamp, body)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
    end
    private_class_method :digest
  end
end
