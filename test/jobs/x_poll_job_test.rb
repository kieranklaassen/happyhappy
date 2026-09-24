require "test_helper"

class XPollJobTest < ActiveJob::TestCase
  SEARCH_URL = "https://api.x.com/2/tweets/search/recent".freeze
  TOKEN = "x-test-bearer-token".freeze

  setup do
    @previous_token = ENV["X_BEARER_TOKEN"]
    ENV["X_BEARER_TOKEN"] = TOKEN
    @source = sources(:x_mentions)
  end

  teardown do
    ENV["X_BEARER_TOKEN"] = @previous_token
  end

  test "a stubbed search response creates items and advances since_id" do
    search = stub_search("search_recent.json", "since_id" => "1830000000000000000", "max_results" => "100")

    assert_difference -> { @source.items.count } => 2, -> { @source.messages.count } => 3 do
      XPollJob.perform_now
    end

    assert_requested search, times: 1
    @source.reload
    assert_equal "1830000000000000103", @source.since_id
    assert_equal BigDecimal("12.535"), @source.month_spend
    assert @source.healthy?

    item = Item.find_by!(source_kind: "x", thread_key: "1830000000000000103")
    assert_equal "maya_writes", item.author_handle
    assert_equal "Maya Chen", item.author_name
    assert_equal "https://x.com/maya_writes/status/1830000000000000103", item.permalink
    message = item.messages.sole
    assert_equal "1830000000000000103", message.external_id
    assert_equal Time.utc(2026, 9, 24, 18, 40, 12), message.occurred_at
    assert_match "briefing layout", message.body
  end

  test "replies in one conversation join one item" do
    stub_search("search_recent.json")

    XPollJob.perform_now

    item = Item.find_by!(source_kind: "x", thread_key: "1830000000000000101")
    assert_equal %w[1830000000000000101 1830000000000000102], item.messages.order(:occurred_at).map(&:external_id)
    assert_equal "maya_writes", item.author_handle
  end

  test "a response with next_token fetches the next page and keeps the first page's newest_id as since_id" do
    stub_search("search_recent_page_1.json")
    second = stub_search("search_recent_page_2.json", "next_token" => "b26v89c19zqg8o3fosbpbf1u8r5i5ytzcd0dfyckbeb9")

    assert_difference -> { @source.messages.count } => 3 do
      XPollJob.perform_now
    end

    assert_requested :get, SEARCH_URL, query: hash_including({}), times: 2
    assert_requested second, times: 1
    @source.reload
    assert_equal "1830000000000000203", @source.since_id
    assert_equal BigDecimal("12.545"), @source.month_spend
  end

  test "AE4: once the limit is reached the next run makes no HTTP call and the source shows paused for budget" do
    @source.update!(month_spend: @source.monthly_limit)
    paused = sources(:x_budget_paused)

    XPollJob.perform_now

    assert_not_requested :get, SEARCH_URL, query: hash_including({})
    assert @source.reload.paused_for_budget?
    assert_equal "1830000000000000000", @source.since_id
    assert paused.reload.paused_for_budget?
  end

  test "a limit too close for one worst-case page pauses before calling" do
    @source.update!(month_spend: @source.monthly_limit - BigDecimal("0.10"))

    XPollJob.perform_now

    assert_not_requested :get, SEARCH_URL, query: hash_including({})
    assert @source.reload.paused_for_budget?
  end

  test "raising the limit resumes a budget-paused source" do
    paused = sources(:x_budget_paused)
    paused.update!(monthly_limit: 20)
    @source.update!(status: :paused)
    search = stub_search("search_recent.json", "query" => paused.selector)

    XPollJob.perform_now

    assert_requested search, times: 1
    assert paused.reload.active?
  end

  test "a new month resets spend and resumes polling" do
    paused = sources(:x_budget_paused)
    paused.update!(month_key: 1.month.ago.strftime("%Y-%m"))
    @source.update!(status: :paused)
    search = stub_search("search_recent.json", "query" => paused.selector)

    XPollJob.perform_now

    assert_requested search, times: 1
    paused.reload
    assert paused.active?
    assert_equal Time.current.strftime("%Y-%m"), paused.month_key
    assert_equal BigDecimal("0.035"), paused.month_spend
    assert_equal "1830000000000000103", paused.since_id
  end

  test "a 429 response records the error and keeps since_id unchanged" do
    stub_request(:get, SEARCH_URL).with(query: hash_including({}))
      .to_return(status: 429, body: file_fixture("x/rate_limited.json").read, headers: json_headers)

    assert_no_difference -> { Message.count } do
      XPollJob.perform_now
    end

    @source.reload
    assert_equal "1830000000000000000", @source.since_id
    assert_match "HTTP 429", @source.last_error
    assert_equal BigDecimal("12.5"), @source.month_spend
    assert @source.active?
  end

  test "a failed later page keeps since_id unchanged" do
    stub_search("search_recent_page_1.json")
    stub_request(:get, SEARCH_URL).with(query: hash_including("next_token" => "b26v89c19zqg8o3fosbpbf1u8r5i5ytzcd0dfyckbeb9"))
      .to_return(status: 503, body: "", headers: json_headers)

    XPollJob.perform_now

    @source.reload
    assert_equal "1830000000000000000", @source.since_id
    assert_match "HTTP 503", @source.last_error
  end

  test "a missing bearer token records the error without calling X" do
    ENV.delete("X_BEARER_TOKEN")

    XPollJob.perform_now

    assert_not_requested :get, SEARCH_URL, query: hash_including({})
    assert_equal "X_BEARER_TOKEN is not set", @source.reload.last_error
  end

  test "manually paused and non-X sources are never polled" do
    @source.update!(status: :paused)

    XPollJob.perform_now

    assert_not_requested :get, SEARCH_URL, query: hash_including({})
  end

  private

  def stub_search(fixture, query = {})
    stub_request(:get, SEARCH_URL)
      .with(query: hash_including(query), headers: { "Authorization" => "Bearer #{TOKEN}" })
      .to_return(status: 200, body: file_fixture("x/#{fixture}").read, headers: json_headers)
  end

  def json_headers
    { "Content-Type" => "application/json" }
  end
end
