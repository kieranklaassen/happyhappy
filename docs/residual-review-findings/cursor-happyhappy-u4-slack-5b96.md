# Residual review findings: U4 Slack connector

Source run: lfg pipeline for U4 (branch `cursor/happyhappy-u4-slack-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so no finding had independent corroboration. No tracker
sink was used; this file is the durable record.

## Residual Review Findings

- P3 `app/services/connectors/slack.rb` (author_for): a failed `users.info` lookup is not cached, so a
  user Slack cannot resolve (for example an external Slack Connect member) triggers a lookup and a
  source `last_error` on every message. Consider a short negative cache if this shows up in health.
- P3 `app/jobs/slack_event_job.rb`: no `retry_on`; a transient database error leaves the job in Solid
  Queue's failed executions for a manual retry rather than retrying automatically. Slack API failures
  never fail the job (they fall back), so this only covers database errors.
- P3 `app/services/connectors/slack.rb` (active_source_for): events for a Slack source whose status is
  `paused` are dropped, not queued. U3 should label paused Slack sources accordingly.
- P3 `test/fixtures/items.yml` (`angry_slack`, owned by U1): its `thread_key` is `1727190000.000100`
  without the `C0COMMUNITY:` channel prefix that KTD2 and this connector use. Harmless today; U15
  may want to align it for realistic end-to-end data.
- P3 `.env.example`: this branch adds `SLACK_BOT_TOKEN`; U13 needs the same variable. Keep one copy
  when the branches merge.
