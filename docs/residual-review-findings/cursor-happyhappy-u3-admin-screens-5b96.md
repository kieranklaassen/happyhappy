# Residual review findings: U3 admin screens

Source run: lfg pipeline for U3 (branch `cursor/happyhappy-u3-admin-screens-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so reviewer agreement is not independent corroboration.
No tracker sink was used; this file is the durable record.

## Residual Review Findings

- P3 `app/models/source.rb` (`belongs_to :default_product, optional: true`): a crafted request with a
  `default_product_id` that matches no product hits the `sources.default_product_id` foreign key and
  returns a 500 instead of a validation error. The UI only offers real products. Fix belongs in the
  U1-owned model: validate `default_product` presence when `default_product_id` is set.
- P3 `app/controllers/sources_controller.rb` (`current_month_spend`, `limit_raised_above_spend?`):
  U8 handoff. The sources form sets a `paused_for_budget` X source back to `active` when its limit is
  raised above this month's spend, because the poller only searches active sources and only unpauses
  on a new month. The month key format (`%Y-%m`) is duplicated here; if U8 adds a
  `Source#current_month_spend` or budget helper, switch this controller to it.
- P3 U9 handoff: classification criteria should read `Product.active` and `Category.active` (with
  `description` and `hint_words`). Retiring from these screens relies on that to drop a product or
  category from new classification while past items keep the label.
- P3 test suite: one unreproduced error appeared on the first full `bin/rails test` run after new
  files were added; more than 25 later full and controller-suite runs were clean and the failing
  output was not captured. Worth watching in CI.
- Deviation: the plan lists `app/controllers/inertia_controller.rb` shared props for navigation. It
  was left unchanged because `AppNav` already reads a static entry list and the current URL, and
  sibling units may touch the same file.
