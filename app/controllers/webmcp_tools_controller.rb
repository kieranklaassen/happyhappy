# WebMCP for signed-in people: the browser registers the MCP tools with document.modelContext and runs
# them here. Like /mcp this is an agent protocol surface, not a page data API. It authenticates with the
# session cookie and Rails' CSRF token, never an agent token.
class WebmcpToolsController < ApplicationController
  include Authentication
  # Declared after the session check so a signed-out caller hears 401 before any CSRF refusal.
  protect_from_forgery with: :exception

  wrap_parameters false
  rescue_from ActionController::InvalidAuthenticityToken do
    render json: { error: "The CSRF token is missing or invalid. Reload the page and try again." },
      status: :unprocessable_content
  end

  def index
    no_store
    render json: { tools: Mcp::ToolRegistry.webmcp_definitions }
  end

  def create
    no_store
    arguments = JSON.parse(request.raw_post.presence || "{}", symbolize_names: true)
    raise JSON::ParserError unless arguments.is_a?(Hash)

    render json: Mcp::ToolRegistry.call(params[:name], arguments, user: Current.user)
  rescue JSON::ParserError
    render json: { error: "The request body must be a JSON object of tool arguments." }, status: :bad_request
  rescue Mcp::ToolRegistry::UnknownTool => error
    render json: { error: error.message }, status: :not_found
  rescue Mcp::ToolRegistry::Failed => error
    render json: { error: error.message }, status: :internal_server_error
  end

  private

  def request_authentication
    render json: { error: "Sign in to happyhappy to use its tools." }, status: :unauthorized
  end

  def no_store
    response.headers["Cache-Control"] = "no-store"
  end
end
