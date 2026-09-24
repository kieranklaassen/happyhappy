# Residual review findings: U9 Jev classification

Source run: lfg pipeline for U9 (branch `cursor/happyhappy-u9-jev-classification-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. No tracker sink was used; this file is the durable record.

## Residual Review Findings

- P2 `app/services/classification/apply.rb` (roll_up), settled KTD2: open messages are those
  received since the last status change, so a claimed item whose only open message is an off-topic
  reply becomes not relevant and leaves the default feed while an agent still holds it. This follows
  KTD2 literally; the plan owner may want claimed and in-progress items to keep their pre-claim
  relevance.
- P3 `app/services/classification/apply.rb` (roll_up): when an item has no open classified messages
  (a job that finishes after a status change), the rollup uses every classified message so the late
  answer still labels the item. KTD2 does not define this case.
- P3 `app/services/classification/apply.rb`: item `anger_probability` is nil when no open message is
  relevant. U13's escalation check must treat nil as below the threshold.
- P3 `app/services/classification/schema_builder.rb`: a product whose slug is `none` would collide
  with the no-product option. U3 could reserve that slug.
- P3 `test/fixtures/files/typesafe/systemone_angry_cora.json`: the answers come from one live Jev run;
  the `model` and `usage` fields are placeholders because only the parsed answers were captured.
