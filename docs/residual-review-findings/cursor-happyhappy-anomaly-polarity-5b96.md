# Residual review findings: U24 anomaly polarity

Source run: lfg pipeline for U24 (branch `cursor/happyhappy-anomaly-polarity-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. No tracker sink was used; this file is the durable record.

## Residual Review Findings

- P3 `db/migrate/20260925160000_add_polarity_to_anomalies.rb`: the backfill calls
  `Anomalies::Polarity`, so it reads the Category and Item models as they are when it runs. If those
  models change shape before an old database migrates, the backfill may need a local copy of the
  mapping.
- P3 `db/migrate/20260925160000_add_polarity_to_anomalies.rb` (down): rolling back gives neutral
  rows a `low` severity because their original severity is not kept.
- P3 `app/services/anomalies/polarity.rb`: volume and uncategorized spikes follow the sentiment mix
  of their driving items at detection time; a reclassification later does not change the polarity
  until the next detection pass extends the row. Relieved sentiment counts toward the positive
  majority.
- P3 `app/frontend/lib/anomaly-format.ts`: day windows read "in a day" rather than "today" or
  "yesterday", because daily windows are whole past calendar days.
