module Mcp
  # Mounts ToolRegistry's MCP server on a stateless Streamable HTTP transport for one authenticated agent.
  # Both are built per request: the agent travels in server_context, and stateless mode keeps no sessions,
  # so nothing is shared between requests or Puma threads.
  #
  #   transport = Mcp::Server.transport_for(agent)
  #   status, headers, body = transport.handle_request(request)
  module Server
    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    module_function

    def transport_for(agent)
      MCP::Server::Transports::StreamableHTTPTransport.new(
        ToolRegistry.mcp_server(agent: agent),
        stateless: true,
        enable_json_response: true,
        serve_subscriptions_listen: false,
        allowed_hosts: allowed_hosts,
        allowed_origins: allowed_origins
      )
    end

    # The public host the app is served on (behind kamal-proxy the Host header is the public name),
    # plus loopback names outside production.
    def allowed_hosts
      hosts = [ public_uri&.host ].compact
      hosts += LOCAL_HOSTS unless Rails.env.production?
      hosts
    end

    def allowed_origins
      [ public_uri&.origin ].compact
    end

    # PUBLIC_BASE_URL, read at boot by config/initializers/omniauth.rb.
    def public_uri
      uri = URI.parse(Rails.configuration.x.public_base_url.to_s)
      uri if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end
  end
end
