# Residual review findings: U16 Custom inbound webhook source

Source run: lfg pipeline for U16 (branch `cursor/happyhappy-u16-custom-webhook-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so reviewer agreement is not independent corroboration.
No tracker sink was used; this file is the durable record. Browser testing was skipped: no
host-native browser and `agent-browser` is not installed; the sources UI is covered by Vitest.

Applied in review: custom thread keys are now prefixed with the source (`source-<id>:<key>`), because
items are unique per source kind plus thread key and two products sending the same `thread_key` (or
the same numeric `id`) would otherwise have merged into one item. Also dropped two needless reloads
on the async path.

## Residual Review Findings

- P2 handoff to U14 (`config/deploy.yml`, `.kamal/secrets`): production needs
  `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, and
  `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` as env secrets. Without them, creating a custom
  source fails with a 500 (Active Record encryption configuration error). Rotating these keys later
  makes stored signing secrets unreadable.
- P2 merge note: this branch adds `db/migrate/20260924190001_add_custom_webhook_to_sources.rb`. U17
  adds its own migration in parallel, so `db/schema.rb` will conflict on the version line and table
  list; regenerate it with `bin/rails db:migrate` after merging both.
- P3 `app/services/connectors/custom.rb` (`classify_inline`): the 10 second sync bound uses
  `Timeout.timeout`, which can interrupt the classifier mid-request, including its product and
  category reads. The message is already committed and the delayed job reclassifies, so no data is
  lost, but a per-request TypeSafe or Faraday timeout would be gentler if `ruby_llm-typesafe` exposes one.
- P3 `app/controllers/webhooks/custom_controller.rb`: the sync rate limit (60 per minute per source)
  uses a process-local memory store, correct only while production runs one Puma worker
  (`WEB_CONCURRENCY: "1"` in `config/deploy.yml`). Switch to `Rails.cache` if that changes.
- P3 `app/controllers/webhooks/custom_controller.rb`: requests without `sync` are not rate-limited
  (KTD18 limits sync only). Each one queues a Jev classification, so a leaked secret could run up
  TypeSafe spend until someone rotates it.
