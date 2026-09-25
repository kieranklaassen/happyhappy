# Residual review findings: U22 real-time processing

Source run: lfg pipeline for U22 (branch `cursor/happyhappy-u22-realtime-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md` (U22 section). Simplify and code
review ran inline because no subagents were spawned, so the review lenses are not independent of each
other and no cross-model peer ran. One finding was applied during review: the routing test showed that
`SolidQueue::RecurringJob` (the hourly prune command) runs on `solid_queue_recurring`, which the old
`*` worker covered, so that queue is now listed on the shared worker. No tracker sink was used; this
file is the durable record.

## Residual Review Findings

- P2 `config/queue.yml`: outbound webhook deliveries share the 3-thread worker with default jobs and
  backfill. An endpoint that hangs for the full 10-second timeouts holds a thread per delivery, which
  delays other deliveries and default jobs (digests, sweeps). Live classification is unaffected. If
  it bites, give `webhooks` its own worker or shorten `WebhookDelivery::TIMEOUT`.
- P3 `config/queue.yml`: the realtime worker is one more forked process inside Puma (roughly one Rails
  process of memory). Size the Hetzner box accordingly; `REALTIME_JOB_THREADS` and `JOB_THREADS` tune
  threads without code changes.
- P3 `app/services/classification/rate_limiter.rb`: the budget is counted per second (20 a second for
  1,200 a minute) with one Solid Cache write per TypeSafe call. It never lets a burst spend the minute's
  budget in its first second, which is stricter than a sliding minute. With the null store (tests) it
  never blocks.
- P3 `app/frontend/pages/items/index.tsx`: the feed now reloads its rows on live pings and every 30
  seconds, on any page and filter, so rows can shift while someone reads a deep page.
- P3 no "classifying..." placeholder (deliberate, see the plan's U22 decisions): relevance is unknown
  until Jev answers and `ItemsQuery` also feeds MCP agents. Classification is about 0.6 s of the
  1.0 s end-to-end p50, so a placeholder would show off-topic chatter briefly for little gain.
- P3 Slack path: Slack messages still take one extra queue hop (`SlackEventJob`, then
  `ClassifyMessageJob`) plus the author and permalink lookups, so they are stored about 300 to 400 ms
  after receipt at p95. Folding classification into `SlackEventJob` would save one poll interval.
- P3 cold first request: the first Intercom or Discord message after a boot takes 100 to 150 ms to
  answer (warm p95 is under 40 ms). Not worth a warm-up hook today.
- P3 harness scope: the dashboard stage models the browser from `use-mood-stream.ts` constants and
  excludes the partial reload request itself (measured by `script/perf`).
