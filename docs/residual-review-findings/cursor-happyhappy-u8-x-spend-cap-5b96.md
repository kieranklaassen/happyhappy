# Residual review findings: U8 X connector with spend cap

Source run: lfg pipeline for U8 (branch `cursor/happyhappy-u8-x-spend-cap-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. Applied in review: overlapping polls are discarded
(`on_conflict: :discard`), and tests now cover the mid-pagination budget pause and unexpected
failures. No tracker sink was used; this file is the durable record.

## Residual Review Findings

- P2 `app/services/connectors/x_budget.rb` (`POST_COST`, `USER_COST`): prices are estimates
  ($0.005 per post, $0.010 per expanded user). Confirm against the first X invoice and adjust the
  constants; X may dedupe reads within a UTC day, so the estimate likely overstates spend.
- P2 `app/services/connectors/x.rb` (poll): when the budget runs out mid-pagination, `since_id`
  still advances to the first page's `newest_id`, so the unread older pages are skipped for good.
  This follows the plan's "advance since_id after calling"; recent search only covers 7 days anyway.
- P3 `app/services/connectors/x_budget.rb` (`remaining`): a source with no monthly limit is treated
  as a zero budget and pauses for budget. U3's source form should require a limit for X sources.
- P3 `app/services/connectors/x.rb` (poll): a post that fails `Items::Ingest` validation fails the
  whole poll and keeps `since_id`, so the same pages are re-read (and re-billed) each run until the
  budget pauses the source. Unlikely because `id` and `created_at` are always requested.
- P3 `DEPLOYING.md` (U14): must list `X_BEARER_TOKEN` and tell operators to set a monthly spending
  limit in the X developer console as a backstop. U8 put that note in `.env.example` only, since
  `DEPLOYING.md` is U14's file.
- P3 Month keys use the app time zone (`Time.current`), matching U1's fixtures; X bills in UTC, so
  the reset can be a few hours off X's own month boundary.
