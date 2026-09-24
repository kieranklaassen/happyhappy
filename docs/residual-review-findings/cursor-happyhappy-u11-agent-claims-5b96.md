# Residual review findings: U11 agent tokens, claims, reports, overdue detection

Source run: lfg pipeline for U11 (branch `cursor/happyhappy-u11-agent-claims-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. Browser testing was skipped: no host-native browser
and no `agent-browser` CLI in this environment; the agents page is covered by
`test/controllers/agents_controller_test.rb` and `app/frontend/pages/agents/index.test.tsx`.
No tracker sink was used; this file is the durable record.

## Applied in review

- Shared `Item::HELD_STATUSES` replaces three copies of the claimed and in-progress list.
- A claim that loses a claim-then-release race now reports `:taken` instead of a confusing
  `:not_claimable` message.
- The agent create response that carries the plaintext token is sent with `Cache-Control: no-store`.

## Residual Review Findings

- P3 `app/services/agents/authenticate.rb`: authentication does not touch `agents.last_used_at`.
  Per the plan, U12 records last use (for example `agent.touch(:last_used_at)` after a
  successful `Agents::Authenticate`).
- P3 `app/services/agents/claim.rb`, `report.rb`, `release.rb`: status moves made by agents write
  one `claimed`, `reported`, `released`, or `reassigned` event carrying `from` and `to` (or
  `status`) data, not a separate `status_changed` event. U10's timeline should render these kinds.
- P3 `app/services/agents/release.rb`: a person's reassign is `Agents::Release.call(item:, actor: user)`.
  U10 (or whichever unit adds the feed's reassign control) should call it rather than
  `Item#change_status!`, so the claim fields clear in the same conditional update.
- P3 `app/models/agent.rb` (`revoke!`): revoking an agent leaves its claims in place. They surface
  as overdue after the report-back window and a person can reassign them. Auto-releasing on revoke
  would be a product decision.
- P3 `app/services/agents/claim.rb`: claiming sets `status_changed_at`, which per KTD2 also resets
  the item's open-messages window used for anger. This matches `Item#change_status!` semantics.
