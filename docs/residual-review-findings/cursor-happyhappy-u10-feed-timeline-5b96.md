# Residual review findings: U10 feed, item timeline, corrections, product overview

Source run: lfg pipeline for U10 (branch `cursor/happyhappy-u10-feed-timeline-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so the review lenses (correctness, security, testing,
performance, API contract, adversarial) are not independent of each other and no cross-model peer ran.
Two review findings were applied (feed page clamp, http-only permalinks). No tracker sink was used;
this file is the durable record.

## Residual Review Findings

- P2 handoff to U9 `app/services/classification/` (apply step): corrections set `product_human_set`,
  `category_human_set`, `sentiment_human_set`, and `relevant_human_set` on the item
  (`app/services/items/correct_label.rb`). Reclassifying a later message must leave human-set labels
  alone, or a person's correction is silently overwritten (R17).
- P3 handoff to U11 `app/services/agents/`: the feed's overdue badge and `overdue` filter read the
  `items.overdue` column only; U11's sweep must set it and clear it on report or release.
- P3 handoff to U11/U12: when a person moves a claimed or in-progress item to new, handled, or
  dismissed, `Items::ChangeStatus` clears `claimed_by_agent` and `claimed_at` and records one
  `status_changed` event with `released_agent`; it does not write a separate `released` event. U11's
  release path and U12's MCP output should read either shape.
- P3 handoff to U12 `app/services/mcp/tools/`: use `ItemsQuery.new(**filters)` (strict; unknown keys and
  bad values raise `ItemsQuery::InvalidFilter` with `#filter`) and return that error to the agent.
  `ItemsQuery.from_params` is the lenient form for request params.
- P3 `app/controllers/product_overviews_controller.rb`: the 30-day chart buckets items by `created_at`
  (first arrival) in `Time.zone`. When U13 introduces `APP_TIME_ZONE`, the buckets follow it
  automatically if it sets `config.time_zone`.
- P3 `test/test_helper.rb` (template, not changed here): Vite's test-mode `autoBuild` can race across
  parallel test workers right after frontend sources change, producing one transient
  `ViteRuby::MissingEntrypointError`; a rerun passes. Consider building `vite-test` once before
  `bin/rails test` in CI (U15).
- P3 `docs/modules/frontend.md`: still uses `home/index` as its example page; the page was removed
  because the root now redirects to the feed. Template doc, left as is.
