require "test_helper"

class Backfill::HttpClientTest < ActiveSupport::TestCase
  BASE_URL = "https://api.example.test/v1"

  setup do
    @sleeps = []
  end

  test "get sends Accept and custom headers, strips a leading slash, and compacts nil params" do
    stub_request(:get, "#{BASE_URL}/items")
      .with(
        query: { "limit" => "50" },
        headers: { "Accept" => "application/json", "Authorization" => "Bearer test-token" }
      )
      .to_return(status: 200, body: { items: [ 1, 2 ] }.to_json)

    client = build_client
    assert_equal({ "items" => [ 1, 2 ] }, client.get("/items", limit: 50, before: nil))
    assert_equal({ "items" => [ 1, 2 ] }, client.get("items", limit: 50))
    assert_empty @sleeps
  end

  test "post encodes body as JSON with Content-Type and Accept headers" do
    stub_request(:post, "#{BASE_URL}/search")
      .with(
        body: { query: "billing", limit: 10 }.to_json,
        headers: {
          "Accept" => "application/json",
          "Authorization" => "Bearer test-token",
          "Content-Type" => "application/json"
        }
      )
      .to_return(status: 200, body: { matches: [ "c1" ] }.to_json)

    client = build_client
    assert_equal({ "matches" => [ "c1" ] }, client.post("/search", { query: "billing", limit: 10 }))
    assert_equal({ "matches" => [ "c1" ] }, client.post("search", { query: "billing", limit: 10 }))
    assert_empty @sleeps
  end

  test "returns an empty hash for an empty 2xx response body" do
    stub_request(:get, "#{BASE_URL}/empty").to_return(status: 204, body: "")

    assert_equal({}, build_client.get("/empty"))
    assert_empty @sleeps
  end

  test "sleeps on 2xx success only when throttle returns a positive wait" do
    stub_request(:get, "#{BASE_URL}/paced").to_return(status: 200, body: { ok: true }.to_json)

    assert_equal({ "ok" => true }, build_client(throttle: ->(_response) { 0.5 }).get("/paced"))
    assert_equal [ 0.5 ], @sleeps

    @sleeps.clear
    [ nil, 0, 0.0, -1.0 ].each do |wait|
      assert_equal({ "ok" => true }, build_client(throttle: ->(_response) { wait }).get("/paced"))
    end
    assert_empty @sleeps
  end

  test "retries 429 using throttle wait or fallback linear backoff" do
    stub_request(:get, "#{BASE_URL}/limited")
      .to_return(
        { status: 429, body: { retry_after: 0.25 }.to_json },
        { status: 200, body: { ok: true }.to_json }
      )

    throttle = ->(response) { response.status == 429 ? 0.25 : nil }
    assert_equal({ "ok" => true }, build_client(throttle: throttle).get("/limited"))
    assert_equal [ 0.25 ], @sleeps

    @sleeps.clear
    stub_request(:get, "#{BASE_URL}/limited-fallback")
      .to_return(
        { status: 429, body: "" },
        { status: 429, body: "" },
        { status: 200, body: { ok: true }.to_json }
      )

    assert_equal({ "ok" => true }, build_client.get("/limited-fallback"))
    assert_equal [ 1.0, 2.0 ], @sleeps
  end

  test "retries 5xx responses with linear backoff until a request succeeds" do
    stub_request(:get, "#{BASE_URL}/unstable")
      .to_return(
        { status: 500, body: "error" },
        { status: 503, body: "unavailable" },
        { status: 200, body: { recovered: true }.to_json }
      )

    assert_equal({ "recovered" => true }, build_client.get("/unstable"))
    assert_equal [ 1.0, 2.0 ], @sleeps
  end

  test "retries transient Faraday timeout and connection failures with linear backoff" do
    stub_request(:get, "#{BASE_URL}/flaky")
      .to_raise(Faraday::TimeoutError.new("execution expired"))
      .then.to_raise(Faraday::ConnectionFailed.new("connection reset"))
      .then.to_return(status: 200, body: { recovered: true }.to_json)

    assert_equal({ "recovered" => true }, build_client.get("/flaky"))
    assert_equal [ 1.0, 2.0 ], @sleeps
  end

  test "raises Error immediately without retrying on non-2xx client responses" do
    stub_request(:get, "#{BASE_URL}/missing").to_return(status: 404, body: { message: "Not Found" }.to_json)
    stub_request(:post, "#{BASE_URL}/forbidden").to_return(status: 403, body: { message: "Forbidden" }.to_json)

    client = build_client

    not_found = assert_raises(Backfill::HttpClient::Error) { client.get("/missing") }
    assert_equal "GET /v1/missing returned 404", not_found.message
    assert_requested :get, "#{BASE_URL}/missing", times: 1

    forbidden = assert_raises(Backfill::HttpClient::Error) { client.post("/forbidden", { id: 1 }) }
    assert_equal "POST /v1/forbidden returned 403", forbidden.message
    assert_requested :post, "#{BASE_URL}/forbidden", times: 1
    assert_empty @sleeps
  end

  test "raises Error after MAX_ATTEMPTS on persistent 429 responses" do
    stub_request(:get, "#{BASE_URL}/limited").to_return(status: 429, body: "")

    error = assert_raises(Backfill::HttpClient::Error) do
      build_client(throttle: ->(_response) { 0.5 }).get("/limited")
    end

    assert_equal "GET /v1/limited returned 429 after #{Backfill::HttpClient::MAX_ATTEMPTS} attempts", error.message
    assert_requested :get, "#{BASE_URL}/limited", times: Backfill::HttpClient::MAX_ATTEMPTS
    assert_equal Array.new(Backfill::HttpClient::MAX_ATTEMPTS - 1, 0.5), @sleeps
  end

  test "raises Error after MAX_ATTEMPTS on persistent 5xx responses" do
    stub_request(:get, "#{BASE_URL}/broken").to_return(status: 502, body: "bad gateway")

    error = assert_raises(Backfill::HttpClient::Error) { build_client.get("/broken") }

    assert_equal "GET /v1/broken returned 502 after #{Backfill::HttpClient::MAX_ATTEMPTS} attempts", error.message
    assert_requested :get, "#{BASE_URL}/broken", times: Backfill::HttpClient::MAX_ATTEMPTS
    assert_equal [ 1.0, 2.0, 3.0, 4.0, 5.0 ], @sleeps
  end

  test "raises Error after MAX_ATTEMPTS on persistent transient Faraday errors" do
    stub_request(:get, "#{BASE_URL}/timeout").to_raise(Faraday::TimeoutError.new("execution expired"))

    timeout_error = assert_raises(Backfill::HttpClient::Error) { build_client.get("/timeout") }
    assert_equal "Faraday::TimeoutError after #{Backfill::HttpClient::MAX_ATTEMPTS} attempts", timeout_error.message
    assert_equal [ 1.0, 2.0, 3.0, 4.0, 5.0 ], @sleeps

    @sleeps.clear
    stub_request(:get, "#{BASE_URL}/down").to_raise(Faraday::ConnectionFailed.new("refused"))

    connection_error = assert_raises(Backfill::HttpClient::Error) { build_client.get("/down") }
    assert_equal "Faraday::ConnectionFailed after #{Backfill::HttpClient::MAX_ATTEMPTS} attempts", connection_error.message
    assert_equal [ 1.0, 2.0, 3.0, 4.0, 5.0 ], @sleeps
  end

  private

  def build_client(headers: { "Authorization" => "Bearer test-token" }, throttle: ->(_response) { nil })
    Backfill::HttpClient.new(
      base_url: BASE_URL,
      headers: headers,
      throttle: throttle,
      sleeper: ->(seconds) { @sleeps << seconds }
    )
  end
end
