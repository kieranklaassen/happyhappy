# Residual review findings: U21 WebMCP for signed-in users

Source run: lfg pipeline for U21 (branch `cursor/happyhappy-u21-webmcp-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so the review lenses are not independent of each other
and no cross-model peer ran. After Kieran's second addendum the implementation adopted the
compound-stack-rails `webmcp` module (template 0.8.0); the browser check runs agent-browser with a
stubbed `document.modelContext` against the dev server. No tracker sink was used; this file is the
durable record.

## Checked in review

- `list_items`, `get_item`, and `list_anomalies` never create a browser agent; only write tools do.
- A signed-out POST gets 401 before the CSRF check, so a stale page hears "sign in" rather than a
  CSRF error; a signed-in POST without the page's CSRF token gets 422.
- An agent bearer token on `/webmcp/tools/:name` is ignored (401 without a session).
- The `webmcp` prop is a lambda, so partial reloads neither rebuild it nor re-register tools.
- Tool internals never reach the browser: a raising tool comes back as an `isError` result with the
  gem's generic text, and the exception goes to `Rails.error`.
- WebMCP registrations use no `exposedTo`, so cross-origin frames cannot see the tools.
- The `list_items` schema after the port is byte-identical to the one on main.

## Residual Review Findings

- P3 `app/frontend/lib/webmcp.ts` (upstream): `registerTools` passes only `readOnlyHint`, so the
  `untrustedContentHint` that `list_items`, `get_item`, and `list_anomalies` declare on `/mcp` does
  not reach browser agents. Fix upstream in the module rather than forking the file.
- P3 `app/controllers/webmcp_tools_controller.rb` (upstream): responses carry no
  `Cache-Control: no-store`. They are POST responses, so shared caches do not store them, but the
  earlier happyhappy controller sent it explicitly.
- P3 `app/controllers/webmcp_tools_controller.rb` (upstream): the rate limit is 60 calls per minute
  per user in a process-local `MemoryStore`, so it resets on deploy and is per Puma process. `/mcp`
  still has no rate limit.
- P3 `app/tools/list_items_tool.rb`: the schema omits `additionalProperties: false` on purpose so
  `ItemsQuery` can refuse an unknown filter by name. Every other tool keeps it.
- P3 `app/frontend/lib/webmcp.ts`: Chrome 148 (the build agent-browser ships) exposes only the older
  `navigator.modelContext`; the module falls back to it. Revisit the fallback when Chrome ships
  `document.modelContext`.
- P3 `.template-manifest.yml`: `template_version` jumped from 0.6.0 to 0.8.0 as instructed, but the
  0.7.0 upgrade entries (Ruby 4 and Node 24, ruby_llm 2, Geneva Drive 0.6, dependency refreshes) are
  not applied. An upgrade agent reading the version would skip them; the manifest carries a comment
  saying so.
- P3 `app/frontend/pages/agents/index.tsx`: browser agents appear in the agents table like token
  agents, told apart only by the `(WebMCP)` name suffix. Revoking one blocks that person's WebMCP
  writes; there is no way to restore it short of deleting the row.
- P3 `app/models/agent.rb`: browser agent claims follow the same report-back window and overdue sweep
  as token agents. That matches "same as normal MCP" but means a person who claims from the browser
  and walks away gets an overdue flag after four hours.
