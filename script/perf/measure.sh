#!/usr/bin/env bash
# Rendering performance harness: reseed the perf fixture, measure the server, then the browser.
# Needs a server on BASE_URL serving a production Vite build, for example:
#
#   VITE_RUBY_PUBLIC_OUTPUT_DIR=vite-perf bin/vite build --mode production
#   VITE_RUBY_PUBLIC_OUTPUT_DIR=vite-perf VITE_RUBY_AUTO_BUILD=false bin/rails s -p 3200
#   npm install --no-save playwright-core
#   script/perf/measure.sh > perf.json
set -euo pipefail
cd "$(dirname "$0")/../.."

bin/rails runner script/perf/seed.rb >&2
server=$(bin/rails runner --skip-executor script/perf/server.rb)
timeline_id=$(bin/rails runner 'puts Message.group(:item_id).order(Arel.sql("COUNT(*) DESC")).limit(1).count.keys.first')
browser=$(TIMELINE_ID="$timeline_id" node script/perf/browser.mjs)

node -e '
const [server, browser] = [JSON.parse(process.argv[1]), JSON.parse(process.argv[2])]
const pages = ["dashboard_today", "dashboard_week", "feed", "timeline", "overview"]
const out = { total_load_main_ms: Math.round(pages.reduce((sum, page) => sum + browser[page].load_main_ms, 0)) }
for (const [page, metrics] of Object.entries(server)) for (const [k, v] of Object.entries(metrics)) out[`${page}.${k}`] = v
for (const [page, metrics] of Object.entries(browser)) for (const [k, v] of Object.entries(metrics)) out[`${page}.${k}`] = v
out.pages_ok = pages.every((page) => browser[page].errors === 0)
console.log(JSON.stringify(out, null, 2))
' "$server" "$browser"
