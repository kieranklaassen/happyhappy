module Agents
  # Outcome of an agent service call. On success `value` holds the agent or item;
  # on failure `error` is one of ERRORS and `message` says why in plain words.
  #
  #   result = Agents::Claim.call(agent: agent, item: item)
  #   result.success? # => false
  #   result.error    # => :taken
  class Result < Data.define(:value, :error, :message)
    ERRORS = %i[missing_token invalid_token revoked taken not_claimable not_holder invalid].freeze

    def self.success(value)
      new(value: value, error: nil, message: nil)
    end

    def self.failure(error, message)
      raise ArgumentError, "unknown agent error #{error.inspect}" unless ERRORS.include?(error)

      new(value: nil, error: error, message: message)
    end

    def success?
      error.nil?
    end

    def failure?
      !success?
    end

    def item
      value if value.is_a?(Item)
    end

    def agent
      value if value.is_a?(Agent)
    end
  end
end
