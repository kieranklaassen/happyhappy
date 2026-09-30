# Residual review findings: U26 anomaly incidents

Source run: lfg pipeline for U26 (branch `cursor/happyhappy-u26-incidents-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. No tracker sink was used; this file is the durable record.

Applied during review: a daily anomaly for a spike already resolved from its hourly row (or the
reverse) re-pinged; new anomalies overlapping a resolved anomaly of the same series now join that
resolved incident silently, and detection correlates before it sends webhooks and urgent alerts.

## Residual Review Findings

- P2 `app/services/anomalies/detect.rb` with `app/jobs/post_anomaly_alert_job.rb`: a new
  high-severity all-sources anomaly still posts the existing urgent alert to the Settings channel as
  well as the incident ping in the product's alert channel. Kept on purpose (the brief keeps the
  Settings channel behavior); the owner may want the urgent alert skipped for products with an alert
  channel.
- P3 `app/services/incidents/correlate.rb`: hourly and daily detection can run at the same time, and
  the find-or-create of an open incident is not locked, so two negative anomalies of one product in
  the same instant could open two incidents. SQLite serializes the writes; the window is small.
- P3 `app/models/incident.rb`: an open incident never closes on its own. When its anomalies all end
  it stays open (and on the incident page) until someone resolves it; a later spike beyond the window
  opens a second incident.
- P3 `app/controllers/webhooks/slack_interactions_controller.rb`: anyone who can see the alert channel
  can resolve with the button (R3: every Every person has full access), and a Slack click carries no
  note because there is no modal; the incident page takes notes.
- P3 test suite: one error in roughly ten full `bin/rails test` runs. The first occurrence came before
  any U26 test existed, and it did not reproduce in eight later runs, so the failing test was not
  identified.
