#!/usr/bin/env bash
# Feed search latency harness (U25). Boots the production environment against
# throwaway databases under tmp/latency-search and runs script/latency/search.rb.
# See README.md.
#
#   script/latency/search.sh                     # 20,000 items, stubbed Jev
#   script/latency/search.sh --items 50000
#   source ~/.config/happyhappy/typesafe.env && script/latency/search.sh --live
set -euo pipefail
cd "$(dirname "$0")/../.."

dir=tmp/latency-search
mkdir -p "$dir"
rm -f "$dir"/*.sqlite3*

export SEARCH_LATENCY_HARNESS=1
export RAILS_ENV=production
export SECRET_KEY_BASE_DUMMY=1
export RAILS_LOG_LEVEL="${RAILS_LOG_LEVEL:-warn}"
export SOLID_QUEUE_SKIP_RECURRING=true
export PRIMARY_DATABASE_URL="sqlite3:$dir/primary.sqlite3"
export QUEUE_DATABASE_URL="sqlite3:$dir/queue.sqlite3"
export CACHE_DATABASE_URL="sqlite3:$dir/cache.sqlite3"
export CABLE_DATABASE_URL="sqlite3:$dir/cable.sqlite3"
export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=latency-harness-primary-key-000000000000
export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=latency-harness-deterministic-key-0000
export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=latency-harness-derivation-salt-00000

bin/rails db:prepare > /dev/null
exec bin/rails runner --skip-executor script/latency/search.rb "$@"
