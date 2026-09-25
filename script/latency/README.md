# Live-path latency harness

Measures how long a live customer message takes to reach each place it shows up,
using the real stack on one machine.

```bash
script/latency/run.sh                        # 50 live messages, 40 ms apart
script/latency/run.sh --backfill 300         # the same burst while 300 backfilled messages classify
script/latency/run.sh --label after          # also writes tmp/latency/after.json
```

## What runs for real

- The production environment (eager loading, Solid Queue, Solid Cable, Solid
  Cache), with every database pointed at throwaway files under `tmp/latency/`
  through `PRIMARY_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CACHE_DATABASE_URL`, and
  `CABLE_DATABASE_URL`. The script refuses to run any other way.
- The Solid Queue supervisor, forked with the workers and threads in
  `config/queue.yml`, exactly as Puma's plugin starts it.
- The webhook controllers (Slack, Intercom, Postmark, custom) with valid
  signatures, and the Discord gateway handler (`Connectors::DiscordBot#handle_message`),
  fed the payloads in `test/fixtures/files/` with fresh ids and timestamps.
- A Solid Cable subscription to the `mood` stream, like an open dashboard.

## What is stubbed

- TypeSafe: sleeps 300 to 900 ms per message (seeded by message id, so before and
  after runs see the same latencies). Every fifth message reads as furious.
- Slack `users.info` and `chat.getPermalink`: 120 ms together. Slack
  `chat.postMessage`: 150 ms.
- Outbound webhook endpoints: 80 ms.
- The browser: the dashboard reload time is modelled from the ping arrival times
  with the constants in `app/frontend/components/mood/use-mood-stream.ts`, and
  excludes the reload request itself (see `script/perf` for that).

`--live N` also times N real TypeSafe calls, one at a time, on stored messages.
It needs `TYPESAFE_API_KEY` in the environment; source it in the same command
(`source ~/.config/happyhappy/typesafe.env && script/latency/run.sh --live 3`)
and never print it.

## Stages

Every process appends `{stage, time}` lines to `tmp/latency/events.jsonl`; the
report takes p50 and p95 per stage over the live messages only.

| Stage | From | To |
|---|---|---|
| webhook ack | request sent | response returned (gateway handler returned for Discord) |
| ingest | request sent | message stored and its classification enqueued |
| queue wait | stored | `ClassifyMessageJob` started |
| classify | job started | classifier answered (includes any rate limiter wait) |
| apply | answered | item committed (the Action Cable ping is sent) |
| cable | committed | ping received by the subscriber |
| dashboard | ping received | modelled dashboard reload |
| escalation | committed | Slack post returned |
| outbound webhook | committed | endpoint answered 200 for `item.classified` |

## Feed search (`search.sh`)

```bash
script/latency/search.sh                     # 20,000 items, 40 keystrokes per query and state
script/latency/search.sh --items 50000
set -a; source ~/.config/happyhappy/typesafe.env; set +a; script/latency/search.sh --live --items 2000 --smart 2
```

The same production setup against `tmp/latency-search/`. It seeds a feed of
`--items` items (1 to 3 messages each, spread over 90 days, every supplied label
written), then times:

| Stage | From | To |
|---|---|---|
| keystroke, encoding pending | `FeedSearch.keystroke` called | feed rows built (keyword hits only, encoding enqueued) |
| keystroke, encoding cached | `FeedSearch.keystroke` called | feed rows built (label filters, boosts, and keywords) |
| smart, first bucket | `FeedSearch.smart` called | the first bucket is readable by the `smart` reload |
| smart, all buckets | `FeedSearch.smart` called | the run is complete |

Smart runs go through the forked Solid Queue supervisor. The page adds
`SMART_COALESCE_MS` (100 ms) and one partial reload on top of the Smart numbers.
Jev is a stub sleeping 300 to 900 ms per call that reads queries by keyword
rules; `--live` encodes and reranks with TypeSafe instead (a few dozen calls).
