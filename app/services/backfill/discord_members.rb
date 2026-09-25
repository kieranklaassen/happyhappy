module Backfill
  # Server roles of Discord message authors, looked up once per author. The
  # gateway sends a message's `member` with it, but REST history does not, so
  # backfilled payloads get the same `member` added before they are ingested,
  # and Messages::AuthorRole can tell Every's team from customers.
  #
  #   members = Backfill::DiscordMembers.new
  #   members.with_member(payload, guild_id) # => payload with "member" => { "roles" => [...] }
  #
  # An author who left the server has no member and stays as the payload was.
  class DiscordMembers
    API_URL = "https://discord.com/api/v10"

    def initialize(token: ENV["DISCORD_BOT_TOKEN"], http: nil, sleeper: nil)
      raise ArgumentError, "DISCORD_BOT_TOKEN is not set" if http.nil? && token.to_s.strip.empty?

      @http = http || HttpClient.new(base_url: API_URL, headers: { "Authorization" => "Bot #{token.strip}" },
        throttle: method(:throttle), **{ sleeper: sleeper }.compact)
      @roles = {}
    end

    def with_member(payload, guild_id)
      return payload if payload["member"].is_a?(Hash) || guild_id.blank?

      roles = roles_for(guild_id, payload.dig("author", "id"))
      roles ? payload.merge("member" => { "roles" => roles }) : payload
    end

    def roles_for(guild_id, user_id)
      return if user_id.blank?

      key = [ guild_id.to_s, user_id.to_s ]
      return @roles[key] if @roles.key?(key)

      @roles[key] =
        begin
          Array(@http.get("/guilds/#{guild_id}/members/#{user_id}")["roles"]).map(&:to_s)
        rescue HttpClient::Error
          nil
        end
    end

    private

    # https://discord.com/developers/docs/topics/rate-limits
    def throttle(response)
      if response.status == 429
        JSON.parse(response.body.to_s)["retry_after"]&.to_f
      elsif response.headers["x-ratelimit-remaining"] == "0"
        response.headers["x-ratelimit-reset-after"]&.to_f
      end
    rescue JSON::ParserError
      nil
    end
  end
end
