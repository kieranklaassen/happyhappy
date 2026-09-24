# The MCP endpoint agents connect to (Streamable HTTP, stateless). Like the webhooks it sits outside the
# session gate and authenticates every request by the agent's bearer token alone.
class McpController < ActionController::Base
  skip_forgery_protection
  wrap_parameters false
  before_action :authenticate

  def handle
    status, headers, body = Mcp::Server.transport_for(@agent).handle_request(request)
    headers = headers.transform_keys(&:downcase)
    headers.except("content-type").each { |name, value| response.headers[name] = value }
    response.headers["Cache-Control"] = "no-store"
    content = +""
    body.each { |part| content << part }
    render body: content, status: status, content_type: headers["content-type"] || "application/json"
  ensure
    body.close if body.respond_to?(:close)
  end

  private

  def authenticate
    token = request.authorization.to_s[/\ABearer\s+(\S+)\s*\z/i, 1]
    result = Agents::Authenticate.call(token: token)
    return unauthorized(result.message) if result.failure?

    @agent = result.agent
    @agent.touch(:last_used_at)
  end

  def unauthorized(message)
    response.headers["WWW-Authenticate"] = %(Bearer realm="happyhappy")
    render json: { error: message }, status: :unauthorized
  end
end
