require "test_helper"

class Backfill::DiscordMembersTest < ActiveSupport::TestCase
  API = Backfill::DiscordMembers::API_URL
  GUILD = "1000000000000000007"
  OTHER_GUILD = "1000000000000000008"
  USER = "900000000000000042"

  setup do
    @sleeps = []
  end

  test "raises ArgumentError when http is nil and token is blank" do
    [ nil, "", "   " ].each do |blank_token|
      error = assert_raises(ArgumentError) { Backfill::DiscordMembers.new(token: blank_token) }
      assert_match "DISCORD_BOT_TOKEN", error.message
    end

    stub_request(:get, "#{API}/guilds/#{GUILD}/members/#{USER}")
      .with(headers: { "Authorization" => "Bot injected-token" })
      .to_return(status: 200, body: { roles: [ "555" ] }.to_json)

    http = Backfill::HttpClient.new(
      base_url: API,
      headers: { "Authorization" => "Bot injected-token" },
      throttle: ->(_) { nil },
      sleeper: ->(_) { }
    )
    members = Backfill::DiscordMembers.new(token: nil, http: http)
    assert_equal [ "555" ], members.roles_for(GUILD, USER)
  end

  test "with_member returns payload unchanged when member is already a Hash or guild_id is blank" do
    members = build_members

    with_existing_member = { "author" => { "id" => USER }, "member" => { "roles" => [ "111" ] } }
    assert_same with_existing_member, members.with_member(with_existing_member, GUILD)

    with_empty_member = { "author" => { "id" => USER }, "member" => {} }
    assert_same with_empty_member, members.with_member(with_empty_member, GUILD)

    payload = { "author" => { "id" => USER } }
    [ nil, "", "   " ].each do |blank_guild|
      assert_same payload, members.with_member(payload, blank_guild)
    end

    assert_not_requested :any, %r{\A#{Regexp.escape(API)}}
  end

  test "with_member fetches roles, stringifies them, and merges member without mutating payload" do
    stub_member(GUILD, USER, { "roles" => [ 555, "666" ] })

    payload = { "id" => "msg-1", "author" => { "id" => USER } }
    enriched = build_members(token: "  test-token  ").with_member(payload, GUILD)

    assert_equal({ "roles" => [ "555", "666" ] }, enriched["member"])
    assert_equal "msg-1", enriched["id"]
    refute payload.key?("member")
  end

  test "with_member attaches an empty roles array when Discord omits roles" do
    stub_member(GUILD, USER, {})

    enriched = build_members.with_member({ "author" => { "id" => USER } }, GUILD)

    assert_equal({ "roles" => [] }, enriched["member"])
  end

  test "with_member returns payload unchanged when author id is missing or lookup fails" do
    members = build_members

    no_author = { "id" => "msg-1" }
    assert_same no_author, members.with_member(no_author, GUILD)
    assert_not_requested :any, %r{\A#{Regexp.escape(API)}}

    stub_request(:get, "#{API}/guilds/#{GUILD}/members/#{USER}").to_return(status: 404, body: "{}")
    departed = { "id" => "msg-2", "author" => { "id" => USER } }
    assert_same departed, members.with_member(departed, GUILD)
  end

  test "roles_for caches lookups per guild_id and user_id" do
    stub_member(GUILD, USER, { "roles" => [ "555" ] })
    stub_member(OTHER_GUILD, USER, { "roles" => [ "777" ] })

    members = build_members

    assert_equal [ "555" ], members.roles_for(GUILD, USER)
    assert_equal [ "555" ], members.roles_for(GUILD.to_i, USER.to_i)
    assert_equal [ "777" ], members.roles_for(OTHER_GUILD, USER)

    assert_requested :get, "#{API}/guilds/#{GUILD}/members/#{USER}", times: 1
    assert_requested :get, "#{API}/guilds/#{OTHER_GUILD}/members/#{USER}", times: 1
  end

  test "roles_for caches nil on HttpClient::Error so departed members are only looked up once" do
    stub_request(:get, "#{API}/guilds/#{GUILD}/members/#{USER}").to_return(status: 404, body: "{}")

    members = build_members

    assert_nil members.roles_for(GUILD, USER)
    assert_nil members.roles_for(GUILD, USER)
    assert_requested :get, "#{API}/guilds/#{GUILD}/members/#{USER}", times: 1
  end

  test "roles_for returns nil without HTTP calls when user_id is blank" do
    members = build_members

    [ nil, "", "   " ].each do |blank_user|
      assert_nil members.roles_for(GUILD, blank_user)
    end

    assert_not_requested :any, %r{\A#{Regexp.escape(API)}}
  end

  test "throttle retries 429 using retry_after" do
    stub_request(:get, "#{API}/guilds/#{GUILD}/members/#{USER}")
      .to_return(
        { status: 429, body: { retry_after: 0.4 }.to_json, headers: { "Content-Type" => "application/json" } },
        { status: 200, body: { roles: [ "555" ] }.to_json, headers: { "Content-Type" => "application/json" } }
      )

    assert_equal [ "555" ], build_members.roles_for(GUILD, USER)
    assert_equal [ 0.4 ], @sleeps
  end

  test "throttle falls back to default backoff when 429 body is invalid JSON" do
    stub_request(:get, "#{API}/guilds/#{GUILD}/members/#{USER}")
      .to_return(
        { status: 429, body: "<html>rate limited</html>" },
        { status: 200, body: { roles: [ "555" ] }.to_json, headers: { "Content-Type" => "application/json" } }
      )

    assert_equal [ "555" ], build_members.roles_for(GUILD, USER)
    assert_equal [ Backfill::HttpClient::DEFAULT_RETRY_SECONDS ], @sleeps
  end

  test "throttle pauses for x-ratelimit-reset-after only when x-ratelimit-remaining is 0" do
    stub_request(:get, "#{API}/guilds/#{GUILD}/members/#{USER}")
      .to_return(
        status: 200,
        body: { roles: [ "555" ] }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "x-ratelimit-remaining" => "0",
          "x-ratelimit-reset-after" => "1.5"
        }
      )
    stub_request(:get, "#{API}/guilds/#{GUILD}/members/900000000000000043")
      .to_return(
        status: 200,
        body: { roles: [ "666" ] }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "x-ratelimit-remaining" => "1",
          "x-ratelimit-reset-after" => "1.5"
        }
      )

    members = build_members
    assert_equal [ "555" ], members.roles_for(GUILD, USER)
    assert_equal [ 1.5 ], @sleeps

    assert_equal [ "666" ], members.roles_for(GUILD, "900000000000000043")
    assert_equal [ 1.5 ], @sleeps
  end

  private

  def build_members(token: "test-token", http: nil)
    Backfill::DiscordMembers.new(token: token, http: http, sleeper: ->(seconds) { @sleeps << seconds })
  end

  def stub_member(guild_id, user_id, body)
    stub_request(:get, "#{API}/guilds/#{guild_id}/members/#{user_id}")
      .with(headers: { "Authorization" => "Bot test-token" })
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end
end
