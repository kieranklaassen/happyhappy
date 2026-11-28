require "test_helper"

class Connectors::XTest < ActiveSupport::TestCase
  SEARCH_URL = "https://api.x.com/2/tweets/search/recent".freeze
  TOKEN = "x-test-bearer-token".freeze

  setup do
    @source = sources(:x_mentions)
  end

  test "invalid JSON in a 200 response records an error without advancing since_id" do
    stub_request(:get, SEARCH_URL).with(query: hash_including({}))
      .to_return(status: 200, body: "<html>not json</html>", headers: json_headers)

    assert_no_difference -> { Message.count } do
      Connectors::X.poll(@source, token: TOKEN)
    end

    @source.reload
    assert_equal "1830000000000000000", @source.since_id
    assert_equal BigDecimal("12.5"), @source.month_spend
    assert_match "X search returned invalid JSON:", @source.last_error
    assert_not_nil @source.last_error_at
  end

  test "Faraday transport errors are recorded on the source without raising" do
    [
      Faraday::TimeoutError.new("execution expired"),
      Faraday::ConnectionFailed.new("connection refused")
    ].each do |error|
      stub_request(:get, SEARCH_URL).with(query: hash_including({})).to_raise(error)

      assert_nothing_raised do
        Connectors::X.poll(@source, token: TOKEN)
      end

      @source.reload
      assert_equal "1830000000000000000", @source.since_id
      assert_equal "#{error.class}: #{error.message}", @source.last_error
      assert_not_nil @source.last_error_at
    end
  end

  test "a post whose author_id is missing from includes.users uses the fallback permalink and omits author from raw_payload" do
    body = {
      data: [
        {
          id: "1830000000000000301",
          text: "Mention from an unexpanded author",
          author_id: "999999999",
          conversation_id: "1830000000000000301",
          created_at: "2026-09-24T19:00:00.000Z"
        }
      ],
      includes: { users: [] },
      meta: { newest_id: "1830000000000000301", result_count: 1 }
    }
    stub_request(:get, SEARCH_URL).with(query: hash_including({}))
      .to_return(status: 200, body: body.to_json, headers: json_headers)

    Connectors::X.poll(@source, token: TOKEN)

    item = Item.find_by!(source_kind: "x", thread_key: "1830000000000000301")
    assert_equal "https://x.com/i/web/status/1830000000000000301", item.permalink
    assert_nil item.author_handle
    assert_nil item.author_name

    message = item.messages.sole
    assert_equal [ "post" ], message.raw_payload.keys
    assert_not message.raw_payload.key?("author")
    assert_equal "1830000000000000301", message.raw_payload.dig("post", "id")
  end

  test "a post without conversation_id falls back to its post id as thread_key" do
    body = {
      data: [
        {
          id: "1830000000000000302",
          text: "Post missing conversation_id",
          author_id: "2244994945",
          created_at: "2026-09-24T19:05:00.000Z"
        },
        {
          id: "1830000000000000303",
          text: "Post with blank conversation_id",
          author_id: "2244994945",
          conversation_id: "",
          created_at: "2026-09-24T19:04:00.000Z"
        }
      ],
      includes: {
        users: [ { id: "2244994945", name: "Maya Chen", username: "maya_writes" } ]
      },
      meta: { newest_id: "1830000000000000302", result_count: 2 }
    }
    stub_request(:get, SEARCH_URL).with(query: hash_including({}))
      .to_return(status: 200, body: body.to_json, headers: json_headers)

    assert_difference -> { @source.items.count } => 2, -> { @source.messages.count } => 2 do
      Connectors::X.poll(@source, token: TOKEN)
    end

    assert Item.exists?(source_kind: "x", thread_key: "1830000000000000302")
    assert Item.exists?(source_kind: "x", thread_key: "1830000000000000303")
  end

  test "error_detail falls back from title to errors[0].message to no detail" do
    stub_request(:get, SEARCH_URL).with(query: hash_including({}))
      .to_return(
        { status: 401, body: { title: "Unauthorized" }.to_json, headers: json_headers },
        { status: 400, body: { errors: [ { message: "Invalid operator" } ] }.to_json, headers: json_headers },
        { status: 502, body: "<html>Bad Gateway</html>", headers: json_headers },
        { status: 500, body: {}.to_json, headers: json_headers }
      )

    Connectors::X.poll(@source, token: TOKEN)
    assert_equal "Connectors::X::Error: X search failed with HTTP 401: Unauthorized", @source.reload.last_error

    Connectors::X.poll(@source, token: TOKEN)
    assert_equal "Connectors::X::Error: X search failed with HTTP 400: Invalid operator", @source.reload.last_error

    Connectors::X.poll(@source, token: TOKEN)
    assert_equal "Connectors::X::Error: X search failed with HTTP 502: no detail", @source.reload.last_error

    Connectors::X.poll(@source, token: TOKEN)
    assert_equal "Connectors::X::Error: X search failed with HTTP 500: no detail", @source.reload.last_error
  end

  test "a 400 mentioning since_id on a paginated follow-up request does not clear since_id" do
    stub_request(:get, SEARCH_URL)
      .with(query: hash_including("since_id" => "1830000000000000000"))
      .to_return(status: 200, body: file_fixture("x/search_recent_page_1.json").read, headers: json_headers)
    second_page = stub_request(:get, SEARCH_URL)
      .with(query: hash_including("since_id" => "1830000000000000000",
        "next_token" => "b26v89c19zqg8o3fosbpbf1u8r5i5ytzcd0dfyckbeb9"))
      .to_return(status: 400, body: { detail: "since_id is invalid on paginated request" }.to_json,
        headers: json_headers)

    assert_no_difference -> { Message.count } do
      Connectors::X.poll(@source, token: TOKEN)
    end

    assert_requested :get, SEARCH_URL, query: hash_including({}), times: 2
    assert_requested second_page, times: 1
    @source.reload
    assert_equal "1830000000000000000", @source.since_id
    assert_match "HTTP 400: since_id is invalid on paginated request", @source.last_error
  end

  test "an empty data response without newest_id keeps since_id and clears prior error" do
    @source.update!(last_error: "HTTP 503: upstream unavailable", last_error_at: 10.minutes.ago)
    stub_request(:get, SEARCH_URL).with(query: hash_including({}))
      .to_return(status: 200, body: { data: [], meta: { result_count: 0 } }.to_json, headers: json_headers)

    assert_no_difference -> { Message.count } do
      Connectors::X.poll(@source, token: TOKEN)
    end

    @source.reload
    assert_equal "1830000000000000000", @source.since_id
    assert_nil @source.last_error
    assert_nil @source.last_error_at
    assert @source.healthy?
    assert_equal BigDecimal("12.5"), @source.month_spend
  end

  private

  def json_headers
    { "Content-Type" => "application/json" }
  end
end
