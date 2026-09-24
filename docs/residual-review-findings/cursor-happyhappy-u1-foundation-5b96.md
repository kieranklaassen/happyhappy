# Residual review findings: U1 foundation

Source run: lfg pipeline for U1 (branch `cursor/happyhappy-u1-foundation-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. No tracker sink was used; this file is the durable record.

## Residual Review Findings

- P3 `app/services/items/ingest.rb` (enqueue_classification): until U9 adds `ClassifyMessageJob`,
  ingest logs a warning and leaves the message unclassified. Resolves when U9 lands.
- P3 `test/support/classify_message_job_stub.rb`: no-op test stand-in for `ClassifyMessageJob`.
  U9 should delete it when the real job lands (the autoloaded class wins either way).
- P3 `app/models/item.rb` (`Item::CLASSIFIED_EVENT`): U13 should subscribe to `"item.classified"`
  inside `Rails.application.config.to_prepare` (or by string) so the initializer does not autoload
  a reloadable model at boot.
- P3 `app/services/classification.rb`: the Choice option keys for categories (name or a derived key)
  are left to U9's schema builder; the fake classifier passes whatever keys a test gives it.
- P3 `app/models/source.rb`: selectors are stripped but not downcased; U7 may want case-insensitive
  matching for inbound email addresses.
