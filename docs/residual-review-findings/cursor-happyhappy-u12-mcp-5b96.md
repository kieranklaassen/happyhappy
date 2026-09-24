# Residual review findings: U12 MCP server

Source run: lfg pipeline for U12 (branch `cursor/happyhappy-u12-mcp-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so the review lenses are not independent of each other
and no cross-model peer ran. Browser testing was skipped: U12 changes no UI pages. No tracker sink
was used; this file is the durable record.

## Checked in review

- Invalid JSON gets a JSON-RPC parse error (400) from the transport, and an unauthenticated request
  gets 401 before the body is dispatched.
- Schema-invalid arguments (a missing `item_id`, a bad enum) come back as tool errors from the
  gem's argument validation; unknown filter keys reach `ItemsQuery.new` and come back as
  `ItemsQuery::InvalidFilter` tool errors.
- GET on `/mcp` answers 405 and DELETE is a no-op 200 from the stateless transport; no session id
  is issued.

## Residual Review Findings

- P3 `app/services/mcp/item_payload.rb`: the latest-message excerpt query duplicates
  `ItemProps#item_rows` (U10). A shared `Message.latest_bodies(item_ids)` would remove the copy;
  left alone to stay inside U12's files.
- P3 `app/controllers/mcp_controller.rb`: every authenticated request writes `agents.last_used_at`
  (and `updated_at`). Cheap on SQLite at agent request rates; throttle it if agents poll hard.
- P3 `app/services/mcp/item_payload.rb` (`detail`): `get_item` returns every message and timeline
  event with no cap. Very long threads produce large payloads.
- P3 `app/services/mcp/server.rb`: the gem always allows loopback hosts, so in production
  `Host: localhost` is also accepted. It still needs a valid bearer token.
- P3 `app/services/mcp/server.rb`: only the `PUBLIC_BASE_URL` host is allowed. If the app is served
  on more than one name, `allowed_hosts` needs the others (U14 deploy).
- P3 `test/test_helper.rb` (not changed here): the first full `bin/rails test` run after the branch
  checkout had one transient error that did not reproduce in three reruns, consistent with the Vite
  test-mode `autoBuild` race U10 recorded.
