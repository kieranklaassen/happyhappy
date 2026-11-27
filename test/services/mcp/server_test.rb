require "test_helper"

class Mcp::ServerTest < ActiveSupport::TestCase
  test "public_uri returns a URI::HTTP for valid http and https URLs" do
    with_public_base_url("https://happyhappy.every.to") do
      uri = Mcp::Server.public_uri

      assert_kind_of URI::HTTP, uri
      assert_equal "happyhappy.every.to", uri.host
      assert_equal "https://happyhappy.every.to", uri.origin
    end

    with_public_base_url("http://staging.every.test:3100/app") do
      uri = Mcp::Server.public_uri

      assert_kind_of URI::HTTP, uri
      assert_equal "staging.every.test", uri.host
      assert_equal "http://staging.every.test:3100", uri.origin
    end
  end

  test "public_uri returns nil for non-HTTP schemes, blank values, missing hosts, and invalid URIs" do
    [
      nil,
      "",
      "   ",
      "/mcp",
      "https://",
      "ftp://files.every.to/export",
      "mailto:support@every.to",
      "javascript:alert(1)",
      "http://bad host:notaport",
      "://broken"
    ].each do |raw_url|
      with_public_base_url(raw_url) do
        assert_nil Mcp::Server.public_uri, "expected nil for #{raw_url.inspect}"
      end
    end
  end

  test "allowed_hosts includes public_uri host and LOCAL_HOSTS outside production" do
    with_public_base_url("https://happyhappy.every.to/app") do
      assert_equal %w[happyhappy.every.to localhost 127.0.0.1 ::1], Mcp::Server.allowed_hosts
    end

    with_public_base_url(nil) do
      assert_equal %w[localhost 127.0.0.1 ::1], Mcp::Server.allowed_hosts
    end
  end

  test "allowed_hosts omits LOCAL_HOSTS in production" do
    with_rails_env("production") do
      with_public_base_url("https://happyhappy.every.to") do
        assert_equal [ "happyhappy.every.to" ], Mcp::Server.allowed_hosts
      end

      with_public_base_url(nil) do
        assert_equal [], Mcp::Server.allowed_hosts
      end
    end
  end

  test "allowed_origins returns the configured origin or an empty array when unset or invalid" do
    with_public_base_url("https://happyhappy.every.to:8443/subpath") do
      assert_equal [ "https://happyhappy.every.to:8443" ], Mcp::Server.allowed_origins
    end

    [ nil, "", "ftp://files.every.to", "http://bad host" ].each do |raw_url|
      with_public_base_url(raw_url) do
        assert_equal [], Mcp::Server.allowed_origins, "expected [] for #{raw_url.inspect}"
      end
    end
  end

  test "transport_for returns a stateless StreamableHTTPTransport wired to ToolRegistry for the agent" do
    agent = agents(:baby_agent)
    transport = Mcp::Server.transport_for(agent)

    assert_instance_of MCP::Server::Transports::StreamableHTTPTransport, transport

    status, headers, payload = call_transport(transport, method: "tools/list")
    assert_equal 200, status
    assert_match "application/json", headers["content-type"]
    assert_nil headers["mcp-session-id"]
    assert_equal ToolRegistry.tools.map(&:tool_name), payload.dig("result", "tools").map { |tool| tool["name"] }

    claim_status, _claim_headers, claim_payload = call_transport(
      transport,
      method: "tools/call",
      params: { name: "claim_item", arguments: { item_id: items(:angry_slack).id } }
    )
    assert_equal 200, claim_status
    assert_not claim_payload.dig("result", "isError")
    assert_equal agent, items(:angry_slack).reload.claimed_by_agent
  end

  test "transport_for enforces allowed_hosts and allowed_origins from public_base_url" do
    with_public_base_url("https://happyhappy.every.to") do
      transport = Mcp::Server.transport_for(agents(:cursor))

      ok_status, _headers, _payload = call_transport(
        transport,
        method: "tools/list",
        host: "happyhappy.every.to",
        origin: "https://happyhappy.every.to"
      )
      assert_equal 200, ok_status

      cross_origin_allowed_status, = call_transport(
        transport,
        method: "tools/list",
        host: "localhost",
        origin: "https://happyhappy.every.to"
      )
      assert_equal 200, cross_origin_allowed_status

      bad_host_status, = call_transport(transport, method: "tools/list", host: "evil.example.com")
      assert_equal 403, bad_host_status

      bad_origin_status, = call_transport(
        transport,
        method: "tools/list",
        host: "happyhappy.every.to",
        origin: "https://evil.example.com"
      )
      assert_equal 403, bad_origin_status
    end
  end

  private

  def with_public_base_url(value)
    original = Rails.configuration.x.public_base_url
    Rails.configuration.x.public_base_url = value
    yield
  ensure
    Rails.configuration.x.public_base_url = original
  end

  def with_rails_env(env)
    original = Rails.env
    Rails.env = ActiveSupport::StringInquirer.new(env)
    yield
  ensure
    Rails.env = original
  end

  def call_transport(transport, method:, params: nil, host: "localhost", origin: nil)
    json_body = { jsonrpc: "2.0", id: 1, method: method, params: params }.compact.to_json
    env = Rack::MockRequest.env_for(
      "http://#{host}/mcp",
      method: "POST",
      input: json_body,
      "HTTP_HOST" => host,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream"
    )
    env["HTTP_ORIGIN"] = origin if origin

    status, headers, body = transport.handle_request(ActionDispatch::Request.new(env))
    normalized_headers = headers.transform_keys(&:downcase)
    content = +""
    body.each { |part| content << part }
    parsed = content.present? && normalized_headers["content-type"].to_s.include?("json") ? JSON.parse(content) : content
    [ status, normalized_headers, parsed ]
  ensure
    body.close if body.respond_to?(:close)
  end
end
