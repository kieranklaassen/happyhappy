require "test_helper"

class Backfill::DiscordTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  API = Backfill::Discord::API_URL
  CHANNEL = "1100000000000000001"
  GUILD = "1000000000000000007"

  setup do
    @source = sources(:discord_spiral)
    @since = 90.days.ago
    @sleeps = []

    stub_discord("/channels/#{CHANNEL}", { "id" => CHANNEL, "type" => 0, "guild_id" => GUILD })
    first_page = 100.times.map { |index| discord_message(3000 - index, at: (index + 1).hours.ago) }
    stub_discord("/channels/#{CHANNEL}/messages", first_page, query: { "limit" => "100" })
    stub_discord("/channels/#{CHANNEL}/messages", [
      discord_message(2900, at: 5.days.ago),
      discord_message(2899, at: 6.days.ago, bot: true),
      discord_message(2898, at: 100.days.ago)
    ], query: { "limit" => "100", "before" => "2901" })

    stub_discord("/guilds/#{GUILD}/threads/active", { "threads" => [
      { "id" => "1200", "parent_id" => CHANNEL },
      { "id" => "1300", "parent_id" => "another-channel" }
    ] })
    stub_discord("/channels/#{CHANNEL}/threads/archived/public", { "has_more" => false, "threads" => [
      { "id" => "1201", "parent_id" => CHANNEL, "thread_metadata" => { "archive_timestamp" => 10.days.ago.iso8601 } },
      { "id" => "1202", "parent_id" => CHANNEL, "thread_metadata" => { "archive_timestamp" => 100.days.ago.iso8601 } }
    ] }, query: { "limit" => "100" })
    stub_discord("/channels/1200/messages", [ discord_message(5000, at: 2.hours.ago, channel: "1200") ],
      query: { "limit" => "100" })
    stub_discord("/channels/1201/messages", [ discord_message(5100, at: 12.days.ago, channel: "1201") ],
      query: { "limit" => "100" })
    stub_discord("/guilds/#{GUILD}/members/900000000000000042", { "roles" => [ "555" ] })
  end

  test "imports channel and thread history since the cutoff as backfill, skipping bots and older messages" do
    stats = nil
    assert_difference -> { Message.count } => 103 do
      stats = backfill.sole
    end

    assert_equal [ 104, 103, 0, 1 ], [ stats.fetched, stats.created, stats.duplicates, stats.skipped ]
    assert_nil stats.error
    messages = @source.messages
    assert_equal 103, messages.where(backfilled: true).count
    refute messages.exists?(external_id: %w[2898 2899])
    assert_equal "#{CHANNEL}:1200", messages.find_by!(external_id: "5000").item.thread_key
    assert_equal "#{CHANNEL}:3000", messages.find_by!(external_id: "3000").item.thread_key
    assert_equal "https://discord.com/channels/#{GUILD}/#{CHANNEL}/3000", messages.find_by!(external_id: "3000").item.permalink
    assert_enqueued_jobs 103, only: ClassifyMessageJob
    assert_not_requested :get, "#{API}/channels/1202/messages", query: hash_including({})
  end

  test "looks up each author's server roles once and marks team authors" do
    Setting.current.update!(team_discord_role_ids: [ "555" ])

    backfill

    assert_equal [ "team" ], @source.messages.where(backfilled: true).distinct.pluck(:author_role)
    assert_requested :get, "#{API}/guilds/#{GUILD}/members/900000000000000042", times: 1
  end

  test "an author without a team role is a customer, and one who left the server is unknown" do
    assert_equal 103, backfill.sole.created
    assert_equal [ "customer" ], @source.messages.where(backfilled: true).distinct.pluck(:author_role)

    Item.where(id: @source.messages.where(backfilled: true).select(:item_id)).destroy_all
    stub_request(:get, "#{API}/guilds/#{GUILD}/members/900000000000000042").to_return(status: 404, body: "{}")
    backfill
    assert_equal [ "unknown" ], @source.messages.where(backfilled: true).distinct.pluck(:author_role)
  end

  test "a rerun creates nothing new" do
    backfill
    clear_enqueued_jobs

    stats = nil
    assert_no_difference [ -> { Message.count }, -> { Item.count } ] do
      stats = backfill.sole
    end
    assert_equal [ 0, 103 ], [ stats.created, stats.duplicates ]
    assert_no_enqueued_jobs only: ClassifyMessageJob
  end

  test "a 429 waits for retry_after and retries" do
    stub_request(:get, "#{API}/channels/#{CHANNEL}")
      .to_return({ status: 429, body: { retry_after: 0.25 }.to_json, headers: { "Content-Type" => "application/json" } },
        { status: 200, body: { id: CHANNEL, type: 0, guild_id: GUILD }.to_json })

    assert_equal 103, backfill.sole.created
    assert_equal [ 0.25 ], @sleeps
  end

  test "an unreadable channel is reported on its source instead of raising" do
    stub_request(:get, "#{API}/channels/#{CHANNEL}").to_return(status: 403, body: { message: "Missing Access" }.to_json)

    stats = backfill.sole
    assert_equal 0, stats.fetched
    assert_match "403", stats.error
  end

  test "a forum channel imports only its threads" do
    stub_discord("/channels/#{CHANNEL}", { "id" => CHANNEL, "type" => 15, "guild_id" => GUILD })

    assert_equal 2, backfill.sole.created
    assert_not_requested :get, "#{API}/channels/#{CHANNEL}/messages", query: hash_including({})
  end

  test "refuses to run without a bot token" do
    assert_raises(ArgumentError) { Backfill::Discord.new(since: @since, token: " ") }
  end

  private

  def backfill
    Backfill::Discord.call(since: @since, token: "test-token", sources: [ @source ], sleeper: ->(seconds) { @sleeps << seconds })
  end

  def stub_discord(path, body, query: nil)
    request = stub_request(:get, "#{API}#{path}").with(headers: { "Authorization" => "Bot test-token" })
    request = request.with(query: query) if query
    request.to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def discord_message(id, at:, channel: CHANNEL, bot: false)
    {
      "id" => id.to_s,
      "type" => 0,
      "channel_id" => channel,
      "timestamp" => at.utc.iso8601(3),
      "content" => "Message #{id} about Spiral",
      "attachments" => [],
      "author" => { "id" => "900000000000000042", "username" => "mayawrites", "global_name" => "Maya", "bot" => bot }
    }
  end
end
