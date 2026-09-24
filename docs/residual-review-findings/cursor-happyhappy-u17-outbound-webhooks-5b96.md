# Residual review findings: U17 outbound webhooks

Source run: lfg pipeline for U17 (branch `cursor/happyhappy-u17-outbound-webhooks-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. Browser testing ran against a local development
server with headless Chrome driven over the DevTools protocol (no `agent-browser` CLI here): sign
in, create an endpoint, reveal the secret, test send to a local receiver that verified the
signature, edit to a failing URL, test send again, and read the index. All checks passed.
No tracker sink was used; this file is the durable record.

## Applied in review

- Any exception while posting (not only a fixed list of network errors) now counts as a failed
  attempt, so a malformed reply cannot leave a delivery stuck as pending.
- The `ItemEvent` after-commit fan-out runs inside `Rails.error.handle`: the timeline event is
  already committed, so a webhook bug is reported and never fails ingest, classification, or claims.
- The endpoint form says "None set up yet." when there are no products or categories to filter by.

## Residual Review Findings

- P3 `app/models/webhook_endpoint.rb`: endpoint URLs are not checked against private or link-local
  addresses. Only signed-in every.to people can register endpoints, so this is accepted for v1;
  add an address allowlist or resolver check if endpoints are ever opened wider.
- P3 `app/controllers/webhook_endpoints_controller.rb` (`test_send`): the test send runs inside the
  web request with 10-second open, write, and read timeouts, so a hanging receiver can hold a Puma
  thread for up to about 30 seconds. Acceptable for a manual button; move it to a job with a
  polling result if it becomes a problem.
- P3 `app/models/webhook_delivery.rb`: the receiver's response body is read fully before the first
  500 characters are kept. Receivers are team-registered; stream with a byte cap if that changes.
- P3 `app/services/webhooks/payload.rb`: `data.summary` on `agent.reported` is agent-written and is
  not listed in `untrusted_fields`, though an agent may quote the customer.
- Note for U15 and U16: `Webhooks::Signature` here matches the interface agreed with U16
  (`sign(secret, body, time:)`, `verify(secret, body, header, tolerance: 300)`); keep whichever copy
  merges first. Both units add `config/initializers/active_record_encryption.rb` and the same test
  keys in `config/environments/test.rb`.
- Note for U11 residuals: `reported` events whose `status` differs from `from` also send
  `item.status_changed`, so status subscribers see agent-driven moves to in progress or handled.
