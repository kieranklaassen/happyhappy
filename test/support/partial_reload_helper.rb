# Repeats the last page request as an Inertia partial reload and returns the props it sent. Unlike the
# gem's inertia_reload_only, it sends the asset version, without which the app answers 409.
#
#   get items_path
#   partial_reload(only: %w[items anomalies])  # => { "items" => [ ... ], "anomalies" => [ ... ], ... }
module PartialReloadHelper
  def partial_reload(only: nil, except: nil)
    page = inertia
    headers = { "X-Inertia" => "true", "X-Inertia-Version" => ViteRuby.digest,
                "X-Inertia-Partial-Component" => page.component }
    headers["X-Inertia-Partial-Data"] = only.join(",") if only
    headers["X-Inertia-Partial-Except"] = except.join(",") if except
    get request.fullpath, headers: headers

    assert_response :success
    response.parsed_body.fetch("props").to_h
  end

  # Every query the block ran that matches. assert_no_queries_match ignores query cache hits, and in
  # tests the cache outlives a request, so it would miss a query the earlier page load also ran.
  def matching_queries(pattern, &block)
    queries = []
    count = ->(*, payload) { queries << payload[:sql] if pattern.match?(payload[:sql]) }
    ActiveSupport::Notifications.subscribed(count, "sql.active_record", &block)
    queries
  end
end
