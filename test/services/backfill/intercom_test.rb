require "test_helper"

class Backfill::IntercomTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include IntercomPayloads

  API = Backfill::Intercom::API_URL

  setup do
    @source = sources(:intercom_inbox)
    @since = 90.days.ago
    @sleeps = []

    stub_intercom(:get, "/me", { "type" => "admin", "app" => { "id_code" => "abc123" } })
    stub_search(nil, { "conversations" => [ { "id" => "c1" } ], "pages" => { "next" => { "starting_after" => "cursor-2" } } })
    stub_search("cursor-2", { "conversations" => [ { "id" => "c2" } ], "pages" => { "next" => nil } })
    # c1: opened two days ago; an admin reply and a customer reply since.
    stub_intercom(:get, "/conversations/c1", conversation("c1", created_at: 2.days.ago, parts_at: [ 1.day.ago, 20.hours.ago ]))
    # c2: opened before the cutoff, with a customer reply inside the window.
    stub_intercom(:get, "/conversations/c2", conversation("c2", created_at: 120.days.ago, parts_at: [ 100.days.ago, 3.days.ago ]))
  end

  test "imports customer messages written since the cutoff from every updated conversation" do
    backfill = nil
    stats = nil
    assert_difference -> { Message.count } => 3, -> { Item.count } => 2 do
      backfill = Backfill::Intercom.new(since: @since, token: "test-token", sleeper: ->(seconds) { @sleeps << seconds })
      stats = backfill.call.sole
    end

    assert_equal 2, backfill.conversations
    assert_equal @source, stats.source
    assert_equal [ 3, 3, 0 ], [ stats.fetched, stats.created, stats.duplicates ]

    c1 = Item.find_by!(source_kind: "intercom", thread_key: "c1")
    assert_equal [ "c1-source", "c1-part-2" ], c1.messages.map(&:external_id)
    assert_equal "https://app.intercom.com/a/inbox/abc123/inbox/conversation/c1", c1.permalink
    assert_equal [ "c2-part-2" ], Item.find_by!(thread_key: "c2").messages.map(&:external_id)
    assert_equal 3, Message.where(source: @source, backfilled: true).count
    assert_enqueued_jobs 3, only: ClassifyMessageJob
  end

  test "a rerun creates nothing new" do
    Backfill::Intercom.call(since: @since, token: "test-token")
    clear_enqueued_jobs

    stats = nil
    assert_no_difference [ -> { Message.count }, -> { Item.count } ] do
      stats = Backfill::Intercom.call(since: @since, token: "test-token").sole
    end
    assert_equal [ 0, 3 ], [ stats.created, stats.duplicates ]
    assert_no_enqueued_jobs only: ClassifyMessageJob
  end

  test "a 429 waits until the rate-limit window resets" do
    freeze_time do
      stub_request(:get, "#{API}/me")
        .to_return({ status: 429, headers: { "X-RateLimit-Remaining" => "0", "X-RateLimit-Reset" => (Time.current.to_i + 7).to_s } },
          { status: 200, body: { app: { id_code: "abc123" } }.to_json })

      Backfill::Intercom.call(since: @since, token: "test-token", sleeper: ->(seconds) { @sleeps << seconds })
    end

    assert_equal [ 7.0 ], @sleeps
  end

  test "a request that times out or gets a 5xx is retried" do
    stub_request(:get, "#{API}/conversations/c1").to_timeout
      .then.to_return(status: 502)
      .then.to_return(status: 200, body: conversation("c1", created_at: 2.days.ago, parts_at: [ 1.day.ago, 20.hours.ago ]).to_json)

    stats = Backfill::Intercom.call(since: @since, token: "test-token", sleeper: ->(seconds) { @sleeps << seconds }).sole

    assert_equal 3, stats.created
    assert_equal [ 1.0, 2.0 ], @sleeps
  end

  test "a request that keeps timing out fails the run instead of hanging" do
    stub_request(:get, "#{API}/me").to_timeout

    error = assert_raises(Backfill::HttpClient::Error) do
      Backfill::Intercom.call(since: @since, token: "test-token", sleeper: ->(seconds) { @sleeps << seconds })
    end
    assert_match "after 6 attempts", error.message
    assert_equal 5, @sleeps.size
  end

  test "reports progress every hundred conversations" do
    ids = 150.times.map { |index| { "id" => "bulk-#{index}" } }
    stub_search(nil, { "conversations" => ids, "pages" => { "next" => nil } })
    stub_request(:get, %r{#{API}/conversations/bulk-\d+})
      .to_return(status: 200, body: conversation("bulk", created_at: 200.days.ago, parts_at: [ 200.days.ago, 200.days.ago ]).to_json)

    reported = []
    Backfill::Intercom.call(since: @since, token: "test-token", progress: ->(count) { reported << count })

    assert_equal [ 100 ], reported
  end

  test "refuses to run without an access token" do
    assert_raises(ArgumentError) { Backfill::Intercom.new(since: @since, token: nil) }
  end

  private

  def stub_intercom(method, path, body)
    stub_request(method, "#{API}#{path}")
      .with(headers: { "Authorization" => "Bearer test-token", "Intercom-Version" => Backfill::Intercom::API_VERSION })
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_search(starting_after, body)
    stub_request(:post, "#{API}/conversations/search")
      .with { |request| JSON.parse(request.body).dig("pagination", "starting_after") == starting_after }
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  # The recorded conversation, rekeyed and re-timed: its source, then an admin
  # reply and a customer reply at parts_at.
  def conversation(id, created_at:, parts_at:)
    intercom_payload("conversation_user_replied").dig("data", "item").tap do |item|
      item["id"] = id
      item["created_at"] = created_at.to_i
      item["source"]["id"] = "#{id}-source"
      item["conversation_parts"]["conversation_parts"].each_with_index do |part, index|
        part["id"] = "#{id}-part-#{index + 1}"
        part["created_at"] = parts_at[index].to_i
      end
    end
  end
end
