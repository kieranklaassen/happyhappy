module Webhooks
  # One signing scheme for inbound and outbound webhooks (KTD17):
  #
  #   X-Happyhappy-Signature: t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<raw body>">
  #
  #   header = Webhooks::Signature.sign(secret, body, time: Time.current)
  #   Webhooks::Signature.verify(secret, body, header) # => true or false
  module Signature
    HEADER = "X-Happyhappy-Signature".freeze

    module_function

    def sign(secret, body, time: Time.current)
      timestamp = time.to_i
      "t=#{timestamp},v1=#{digest(secret, timestamp, body)}"
    end

    def verify(secret, body, header, tolerance: 300)
      return false if secret.blank? || header.blank?

      parts = header.to_s.split(",").map { |part| part.strip.split("=", 2) }
      timestamp = parts.find { |key, _| key == "t" }&.last
      signatures = parts.select { |key, _| key == "v1" }.map(&:last)
      return false unless timestamp&.match?(/\A\d+\z/) && signatures.any?
      return false if (Time.current.to_i - timestamp.to_i).abs > tolerance

      expected = digest(secret, timestamp.to_i, body)
      signatures.any? { |signature| ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected) }
    end

    def digest(secret, timestamp, body)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
    end
  end
end
