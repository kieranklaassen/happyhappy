module Agents
  # Resolves a plaintext bearer token to its agent. Tokens are stored only as digests.
  #
  #   Agents::Authenticate.call(token: "…") # => Result with #agent, or :missing_token,
  #                                         #    :invalid_token, :revoked
  class Authenticate
    def self.call(token:)
      token = token.to_s.strip
      return Result.failure(:missing_token, "An agent token is required.") if token.empty?

      agent = Agent.find_by(token_digest: Agent.digest(token))
      return Result.failure(:invalid_token, "The agent token is not recognized.") unless agent
      return Result.failure(:revoked, "The agent token was revoked.") if agent.revoked?

      Result.success(agent)
    end
  end
end
