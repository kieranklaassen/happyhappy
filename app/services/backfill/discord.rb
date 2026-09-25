module Backfill
  # Imports each active Discord source's channel history since a cutoff through
  # the REST API: the channel's own messages plus its active and archived public
  # threads (a forum channel has only threads). Messages go through
  # Connectors::Discord.ingest as backfill, oldest first so replies find the item
  # they answer, and dedupe on the message id, so a rerun creates nothing new.
  # Each author's server roles are added to the payload (DiscordMembers) so the
  # message's author role is known.
  #
  #   Backfill::Discord.call(since: 90.days.ago) # => [Backfill::Stats, ...]
  class Discord
    API_URL = "https://discord.com/api/v10"
    PAGE_SIZE = 100
    FORUM_TYPES = [ 15, 16 ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(since:, token: ENV["DISCORD_BOT_TOKEN"], sources: Source.discord.active, sleeper: nil)
      raise ArgumentError, "DISCORD_BOT_TOKEN is not set" if token.to_s.strip.empty?

      @since = since
      @sources = sources
      @http = HttpClient.new(base_url: API_URL, headers: { "Authorization" => "Bot #{token.strip}" },
        throttle: method(:throttle), **{ sleeper: sleeper }.compact)
      @members = DiscordMembers.new(http: @http)
      @active_threads = {}
    end

    def call
      @sources.map { |source| backfill(source) }
    end

    private

    def backfill(source)
      stats = Stats.new(source)
      channel = @http.get("/channels/#{source.selector}")
      guild_id = channel["guild_id"]

      import(source.selector, guild_id, stats) unless FORUM_TYPES.include?(channel["type"])
      threads(channel).each do |thread|
        import(thread["id"], guild_id, stats, parent_channel_id: source.selector)
      end
      stats
    rescue HttpClient::Error => error
      stats.error = error.message
      stats
    end

    # REST messages omit guild_id, which the connector requires of a guild message.
    def import(channel_id, guild_id, stats, parent_channel_id: nil)
      history(channel_id).reverse_each do |payload|
        stats.fetched += 1
        payload = @members.with_member(payload.merge("guild_id" => guild_id), guild_id)
        stats.record(Connectors::Discord.ingest(payload, parent_channel_id: parent_channel_id, backfill: true))
      end
    end

    # Newest first, as the API pages them, stopping at the cutoff.
    def history(channel_id)
      messages = []
      before = nil
      loop do
        page = @http.get("/channels/#{channel_id}/messages", limit: PAGE_SIZE, before: before)
        recent = page.take_while { |message| Time.iso8601(message["timestamp"]) >= @since }
        messages.concat(recent)
        break if recent.size < PAGE_SIZE

        before = page.last["id"]
      end
      messages
    end

    def threads(channel)
      active = active_threads(channel["guild_id"]).select { |thread| thread["parent_id"] == channel["id"] }
      (active + archived_threads(channel["id"])).uniq { |thread| thread["id"] }
    end

    def active_threads(guild_id)
      @active_threads[guild_id] ||= @http.get("/guilds/#{guild_id}/threads/active").fetch("threads", [])
    end

    # Archived threads come newest-archived first; one archived before the
    # cutoff cannot hold a message after it.
    def archived_threads(channel_id)
      threads = []
      before = nil
      loop do
        page = @http.get("/channels/#{channel_id}/threads/archived/public", limit: PAGE_SIZE, before: before)
        batch = page.fetch("threads", [])
        recent = batch.select { |thread| archived_at(thread) >= @since }
        threads.concat(recent)
        break unless page["has_more"] && batch.any? && recent.size == batch.size

        before = batch.last.dig("thread_metadata", "archive_timestamp")
      end
      threads
    end

    def archived_at(thread)
      Time.iso8601(thread.dig("thread_metadata", "archive_timestamp"))
    end

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
