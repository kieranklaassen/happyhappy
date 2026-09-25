# frozen_string_literal: true

require "test_helper"

class ApplicationToolTest < ActiveSupport::TestCase
  class EchoTool < ApplicationTool
    tool_name "test_echo"
    description "Echoes text back."
    input_schema(properties: { text: { type: "string" } }, required: [ "text" ], additionalProperties: false)

    def call
      raise Error, "Nothing to echo." if arguments[:text].blank?
      return { holder: agent.name } if arguments[:text] == "agent"

      arguments[:text] == "json" ? { echoed: user.email_address } : arguments[:text]
    end
  end

  setup { @context = { user: users(:one) } }

  def text(response) = response.to_h[:content].first[:text]

  test "a String result is returned verbatim" do
    response = EchoTool.call(text: "hi", server_context: @context)

    assert_equal "hi", text(response)
    assert_nil response.structured_content
  end

  test "any other result is serialized as JSON and also sent as structuredContent" do
    response = EchoTool.call(text: "json", server_context: @context)

    assert_equal({ "echoed" => "one@example.com" }, JSON.parse(text(response)))
    assert_equal({ "echoed" => "one@example.com" }, response.structured_content)
  end

  test "ApplicationTool::Error becomes an isError result, not an exception" do
    response = EchoTool.call(text: " ", server_context: @context)
    assert response.error?
    assert_equal "Nothing to echo.", text(response)
  end

  test "without a user or an agent the tool refuses before running" do
    response = EchoTool.call(text: "hi", server_context: { user: nil, agent: nil })
    assert response.error?
    assert_match(/sign in/i, text(response))
  end

  test "an MCP agent acts as itself" do
    assert_no_difference -> { Agent.count } do
      response = EchoTool.call(text: "agent", server_context: { agent: agents(:cursor) })

      assert_equal({ "holder" => "Cursor" }, response.structured_content)
    end
  end

  test "a signed-in person acts through their browser agent, created on first use" do
    user = users(:every_ana)

    response = assert_difference -> { Agent.count } => 1 do
      EchoTool.call(text: "agent", server_context: { user: })
    end

    assert_equal({ "holder" => "Ana Every (WebMCP)" }, response.structured_content)
    assert_not_nil user.reload.browser_agent.last_used_at
  end
end
