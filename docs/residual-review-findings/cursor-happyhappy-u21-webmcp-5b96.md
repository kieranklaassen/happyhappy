# Residual review findings: U21 WebMCP for signed-in users

Source run: lfg pipeline for U21 (branch `cursor/happyhappy-u21-webmcp-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so the review lenses are not independent of each other
and no cross-model peer ran. After Kieran's addendum the implementation was reshaped to Thinkroom's
WebMCP modules; the browser check is now `npm run check:webmcp` (Playwright) against `bin/dev`. No
tracker sink was used; this file is the durable record.

## Checked in review

- `list_items`, `get_item`, and `list_anomalies` never create a browser agent; only write tools do.
- A signed-out POST gets 401 before the CSRF check, so a stale page hears "sign in" rather than a
  CSRF error; a signed-in POST without the page's CSRF token gets 422.
- An agent bearer token on `/webmcp/tools/:name` is ignored (401 without a session).
- The interpreter only fetches `/webmcp/tools/` on the page origin, and the `webmcp` prop is a lambda,
  so partial reloads neither rebuild it nor re-register tools.
- Tool internals never reach the browser: a raising tool answers 500 with the gem's generic
  "Internal error calling tool" text, and the exception goes to `Rails.error`.
- WebMCP registrations use no `exposedTo`, so cross-origin frames cannot see the tools.
- The `list_items` schema after the refactor is byte-identical to the one on main.

## Residual Review Findings

- P3 `app/frontend/lib/webmcp_execute.ts`: like Thinkroom's interpreter, it forwards only the declared
  `body_params`, so an undeclared argument (say `mood`) is dropped in the browser instead of refused
  the way `/mcp` refuses it. The schema says `additionalProperties: false`, and every declared
  argument is still validated on the server.
- P3 `app/frontend/lib/webmcp.ts`: Chrome 148 (the build agent-browser ships) exposes only the older
  `navigator.modelContext` with `registerTool`, and lists our tools with `annotations: {}`, so the
  read-only and untrusted-content hints do not reach that build yet. The current draft's
  `document.modelContext` is preferred when present. Revisit when Chrome ships `document.modelContext`.
- P3 `app/frontend/pages/agents/index.tsx`: browser agents appear in the agents table like token
  agents, told apart only by the `(WebMCP)` name suffix. Revoking one blocks that person's WebMCP
  writes; there is no way to restore it short of deleting the row.
- P3 `app/models/agent.rb`: browser agent claims follow the same report-back window and overdue sweep
  as token agents. That matches "same as normal MCP" but means a person who claims from the browser
  and walks away gets an overdue flag after four hours.
- P3 `app/controllers/webmcp_tools_controller.rb`: no rate limit, matching `/mcp`. Both surfaces rely
  on authentication alone.
