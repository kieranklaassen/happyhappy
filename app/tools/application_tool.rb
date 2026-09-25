# frozen_string_literal: true

# Base class for every agent tool (docs/modules/webmcp.md). A tool is an
# MCP::Tool, so the official SDK's DSL declares it once (`tool_name`,
# `description`, `input_schema`, `annotations`), and ToolRegistry serves the
# same class to MCP clients and to WebMCP browser agents.
#
# Subclasses implement `#call` and return a String or anything JSON-serializable;
# raise ApplicationTool::Error for a failure the agent should read (it becomes
# an `isError` result, never a 500).
#
# happyhappy acts two ways: `/mcp` agents arrive as `agent` (bearer token, no
# user), and WebMCP calls arrive as the signed-in `user`, whose writes go through
# their browser agent (Agent.browser_for). Tools never run without one of them.
# A JSON result also travels as `structuredContent`, which happyhappy's MCP
# clients read.
class ApplicationTool < MCP::Tool
  class Error < StandardError; end

  def self.call(server_context:, **arguments)
    user, agent = server_context.values_at(:user, :agent)
    return error_response("Sign in to use #{tool_name}.") unless user || agent

    text_response(new(user:, agent:, arguments:).call)
  rescue Error => e
    error_response(e.message)
  end

  def self.text_response(value)
    return MCP::Tool::Response.new([ { type: "text", text: value } ]) if value.is_a?(String)

    MCP::Tool::Response.new([ { type: "text", text: value.to_json } ], structured_content: value.as_json)
  end

  def self.error_response(message)
    MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
  end

  attr_reader :user, :arguments

  def initialize(user:, arguments:, agent: nil)
    @user = user
    @agent = agent
    @arguments = arguments
  end

  def call
    raise NotImplementedError, "#{self.class.name} must implement #call"
  end

  private

  # The agent that holds claims and writes reports. Created for a signed-in
  # person only on their first write, so read tools never add an agents row.
  def agent
    @agent ||= Agent.browser_for(user).tap { |browser| browser.touch(:last_used_at) }
  end
end
