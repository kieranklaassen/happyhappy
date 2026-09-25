# frozen_string_literal: true

# Server-side cost per page against the perf fixture (development only):
#
#   bin/rails runner --skip-executor script/perf/server.rb   # prints JSON
#
# For each page: median wall time over RUNS requests, SQL queries per request (an N+1 shows up as a
# count that grows with the data), and response bytes. `dashboard_reload` is the partial reload a live
# update triggers.
require "action_dispatch/testing/integration"
require "action_dispatch/testing/test_request"

abort "script/perf/server.rb only runs in development" unless Rails.env.development?

RUNS = Integer(ENV.fetch("RUNS", 5))
longest = Message.group(:item_id).order(Arel.sql("COUNT(*) DESC")).limit(1).count.keys.first
PAGES = {
  "dashboard_today" => "/",
  "dashboard_week" => "/?range=7d",
  "feed" => "/items",
  "feed_deep" => "/items?page=60",
  "timeline" => "/items/#{longest}",
  "overview" => "/products/cora/overview"
}.freeze

user = User.find_or_create_by!(email_address: "perf@every.to") { |record| record.name = "Perf" }
session_record = user.sessions.create!
jar = ActionDispatch::TestRequest.create.cookie_jar
jar.signed[:session_id] = session_record.id

app = ActionDispatch::Integration::Session.new(Rails.application)
app.host = "localhost"
app.cookies["session_id"] = jar[:session_id]

queries = 0
ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
  queries += 1 unless payload[:name].in?([ "SCHEMA", "CACHE" ]) || payload[:cached]
end

def measure(app, path, headers, queries_ref)
  samples = Array.new(RUNS + 1) do
    before = queries_ref.call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    app.get(path, headers: headers)
    raise "#{path} answered #{app.response.status}" unless app.response.status == 200

    [ (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000, queries_ref.call - before, app.response.body.bytesize ]
  end.drop(1)
  ms = samples.map(&:first).sort
  { server_ms: ms[ms.size / 2].round(1), queries: samples.last[1], bytes: samples.last[2] }
end

count = -> { queries }
results = PAGES.to_h { |name, path| [ name, measure(app, path, {}, count) ] }

version = JSON.parse(app.response.body[%r{<script[^>]*data-page[^>]*>(.*?)</script>}m, 1])["version"]
results["dashboard_reload"] = measure(app, "/?range=7d", {
  "X-Inertia" => "true", "X-Inertia-Version" => version.to_s,
  "X-Inertia-Partial-Component" => "home/index", "X-Inertia-Partial-Data" => "scene,today"
}, count)

session_record.destroy
puts JSON.pretty_generate(results)
