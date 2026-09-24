# Residual review findings: U15 end-to-end flows and CI

Source run: lfg pipeline for U15 (branch `cursor/happyhappy-u15-e2e-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline (no subagents available in this run). Browser tests were skipped: no UI page changed.

## Applied in this unit

- U9 residual (assumed default from the parent): a claimed or in-progress item with no relevant
  message since the claim keeps its labels, relevance, and anger in `Classification::Apply`.
  `Escalations::Check` now refuses an off-topic triggering message, so the kept anger cannot
  escalate on an off-topic reply.
- U6, U7, U14 residual: `body`, `text`, `subject`, and `attachments` are filtered from request
  parameters, and `SlackEventJob` no longer logs its envelope.
- U10 residual: `bin/ci` builds the Vite test assets before the parallel Rails tests (the GitHub
  workflow already did); `test/ci/workflow_test.rb` asserts the order and every gate.
- U2 residual: the real webhook and `/mcp` routes are asserted to answer unauthenticated requests
  themselves rather than redirecting to sign-in.
- U4 residual: the `angry_slack` fixture's thread key now carries the `C0COMMUNITY:` prefix.
- U18 gap: agent claims, reports, releases, and the overdue sweep move items with `update_all`, so
  they skipped `Item`'s after_commit `MoodChannel` ping. `ItemEvent` now pings for those event kinds.
- `.env.example` on main listed `SLACK_BOT_TOKEN` and `PUBLIC_BASE_URL` twice; the second copies are gone.

## Residual review findings

- P3 `app/services/escalations/check.rb` (`trigger`): when an item.classified event has no message,
  the fallback trigger is the angriest open message, which may be off-topic and now blocks the
  escalation. No production caller publishes without a message today.
- P3 `config/initializers/filter_parameter_logging.rb`: matching is partial, so keys such as Slack's
  `event_context` are filtered too. Log-only effect.
- P3 `app/frontend/components/app-nav.tsx` (U2 residual): still no sign-out control. Left to the
  unit that owns navigation (U18 owns the home page).
- P2 pre-existing on main `test/controllers/dev_login/sessions_controller_test.rb`: order-dependent.
  Run alone it fails at every seed (the stand-in routes lack `pwa_manifest_path` used by the layout,
  and a `dev_login_path` helper leaks from `with_routing`); in the full parallel suite it fails about
  one run in ten. Owned by U2's files; not changed here.
