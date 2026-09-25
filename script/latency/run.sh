#!/usr/bin/env bash
# Live-path latency harness. Boots the production environment against throwaway
# databases under tmp/latency and runs script/latency/run.rb. See README.md.
#
#   script/latency/run.sh                         # 50-message burst
#   script/latency/run.sh --backfill 300          # the same burst while a backfill classifies
#   script/latency/run.sh --label before > before.md
set -euo pipefail
cd "$(dirname "$0")/../.."

dir=tmp/latency
mkdir -p "$dir"
rm -f "$dir"/*.sqlite3* "$dir"/events.jsonl

export LATENCY_HARNESS=1
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
export SLACK_SIGNING_SECRET=latency-slack-signing-secret
export SLACK_BOT_TOKEN=xoxb-latency-harness
export INTERCOM_CLIENT_SECRET=latency-intercom-secret
export POSTMARK_INBOUND_USER=latency
export POSTMARK_INBOUND_PASSWORD=latency-password

bin/rails db:prepare > /dev/null
exec bin/rails runner --skip-executor script/latency/run.rb "$@"
