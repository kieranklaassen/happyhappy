# Residual review findings: U13 Slack escalations and daily digests

Source run: lfg pipeline for U13 (branch `cursor/happyhappy-u13-slack-alerts-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. No tracker sink was used; this file is the durable record.
Applied in review: escaped the escalation fallback text (a customer handle such as `<!channel>` could
ping a channel) and escaped Slack link URLs.

## Residual Review Findings

- P3 `app/services/slack/formatting.rb` (`item_url`): item links point at `/items/:id`, the route U10
  owns, built from `PUBLIC_BASE_URL`. Switch to the `item_url` route helper once U10 lands. When
  `PUBLIC_BASE_URL` is unset the link falls back to `http://localhost:3000`; U14 lists the variable as
  a required production secret.
- P3 `app/services/slack/digest_message.rb` (`handled_counts`): "what agents handled" counts distinct
  items with a `reported` event by an agent whose `data.status` is `handled`, matching U1's fixture
  shape. U11's `Agents::Report` must keep writing `status` into the reported event's data.
- P3 `config/initializers/item_events.rb`: the escalation check runs synchronously inside whatever
  publishes `item.classified`. U9 should publish after the classification is saved; a check that
  raises fails the publisher so classification retries, and the per-thread dedupe keeps the retry
  from double-posting.
- P3 `app/services/escalations/check.rb`: a retired product that still has a Slack channel can
  escalate. Classification should never choose a retired product, so no guard was added.
- P3 `app/jobs/post_escalation_job.rb`, `app/jobs/post_digest_job.rb`: if Slack accepts the post but
  saving the ts fails, the retry posts a second time. Rare; accepted.
- P3 `app/jobs/post_escalation_job.rb`, `app/jobs/post_digest_job.rb`: a permanent Slack error (for
  example `channel_not_found`) fails the job and keeps the unposted record with `last_error`; nothing
  re-sends it after the channel is fixed. A future settings screen could offer a resend.
