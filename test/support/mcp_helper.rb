module McpHelper
  # Sends one JSON-RPC request to /mcp the way a Streamable HTTP client does.
  def mcp_request(method, params = nil, token: "cursor-test-token", headers: {})
    body = { jsonrpc: "2.0", id: 1, method: method, params: params }.compact
    auth = token ? { "Authorization" => "Bearer #{token}" } : {}
    post mcp_path, params: body.to_json, headers: {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream"
    }.merge(auth, headers)
    response.parsed_body
  end

  def mcp_tool(name, arguments = {}, **options)
    mcp_request("tools/call", { name: name, arguments: arguments }, **options).fetch("result")
  end

  def tool_error_text(result)
    assert result["isError"], "expected a tool error, got #{result.inspect}"
    result["content"].first["text"]
  end

  def tool_payload(result)
    assert_not result["isError"], "unexpected tool error: #{result.dig('content', 0, 'text')}"
    assert_equal result["structuredContent"], JSON.parse(result["content"].first["text"])
    result["structuredContent"]
  end
end
