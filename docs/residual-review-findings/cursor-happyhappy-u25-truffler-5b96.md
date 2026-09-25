# Residual review findings: U25 feed search with truffler

Source run: lfg pipeline for U25 (branch `cursor/happyhappy-u25-truffler-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify, code review, and the
browser pass (agent-browser against the dev server) ran inline because no subagents were available.
No tracker sink was used; this file is the durable record.

## Residual Review Findings

- P2 `app/models/item/searchable.rb`: every new item and every new message (it moves
  `last_message_at`, which `churn_risk` watches) asks Jev `churn_risk` at live priority, including items that a
  history backfill (DEPLOYING.md, "Backfilling history") creates. Truffler cannot be told a record is
  backfilled from the model callback. Cost is small (10 items per call, about a dollar per 20,000
  long threads at truffler's default price) and bounded by `config.headroom = 0.5`, but it spends
  during a history import.
- P2 `config/initializers/truffler.rb`: truffler's budget and `Classification::RateLimiter` count
  separately. Truffler keeps to half of `TYPESAFE_REQUESTS_PER_MINUTE`, and the classifier limiter
  allows the full limit, so a classification burst during heavy search could exceed the account
  limit. TypeSafe would then answer 429, which both sides retry.
- P3 `script/latency/run.sh` (U22 harness), same machine, 50 live messages: truffler's after-commit
  work (labeling queue row, job enqueue, FTS refresh) moves "apply" from p50 5 / p95 22 to 26 ms to
  p50 11 / p95 49 to 79 ms and "ingest" p50 by about 5 ms. End-to-end dashboard p50 stayed at about
  1.0 to 1.1 s in both runs.
- P3 `app/models/item/searchable.rb`: `config.cost_per_million_tokens` is truffler's default
  (0.042 dollars); the backfill spend cap and the cost estimate in `docs/search.md` rely on it until
  TypeSafe's real price is set.
- P3 `app/controllers/items_controller.rb`: search results are the top 50 with no pagination;
  the Smart search Strong, Possible, and Unlikely buckets cover the top 30.
- P3 `app/tools/search_items_tool.rb`: an agent's first search of a new query can hold a Puma thread
  for up to 2 seconds while the encoding lands (polling the cache every 100 ms).
- P3 `app/frontend/components/search/smart-results.tsx`: bucket rows do not show the rerank score.
- P3 lenses are enabled for every signed-in user, but nothing in the UI creates or manages them yet.

## Resolved by truffler 0.1.1

- `FeedSearch::EncodingClient` is gone: truffler 0.1.1 sends the label vocabulary with the word-role
  questions, turns a keyword naming an applied label into a label term and a stopword into filler,
  and stops requiring keyword hits when a label filter applies.
- The `none` product option is filterable: truffler's "no option" answer is now `truffler:none`.
