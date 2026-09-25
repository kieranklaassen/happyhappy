# Residual review findings: U20 anomaly detection

Source run: lfg pipeline for U20 (branch `cursor/happyhappy-u20-anomalies-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. Review found one bug (a spike found and ended within one
scan still sent `anomaly.detected`), fixed with a regression test. No tracker sink was used; this file
is the durable record.

## Residual Review Findings

- P3 `app/frontend/pages/home/index.tsx`: the live dashboard partial reload asks only for `scene` and
  `today`, so a new callout appears on the next full visit, not live. Add `anomalies` to the reload
  keys once the dashboard rendering rework lands (kept out of this unit to avoid touching that code).
- P3 `app/services/anomalies/series.rb` (customer_key): duplicates `MoodScene#author_key` on plucked
  columns. Left separate so `MoodScene`, which the dashboard rework owns, stays untouched; fold into one
  helper afterwards.
- P3 `app/services/anomalies/detect.rb`: hourly baselines mix all hours of the day, so a normal morning
  rush after a quiet night can look like a spike on a small series. The minimum count, minimum lift,
  and sensitivity guard against it; a same-hour-of-day baseline is the next step if it proves noisy.
- P3 `app/models/detected_anomaly.rb` (category): looks up the category per row, one query per
  category anomaly in lists of up to 50.
- P3 `app/services/anomalies/series.rb`: messages with a null `author_role` count as customer messages
  once that column lands. The classification worker should backfill or default the column if team
  messages already exist.
- P3 `app/models/webhook_endpoint.rb` (matches_anomaly?): sentiment filters do not apply to
  `anomaly.detected`; a category filter passes only category anomalies in those categories.
