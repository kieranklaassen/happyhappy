# Residual review findings: U2 Every SSO and every.to gate

Source run: lfg pipeline for U2 (branch `cursor/happyhappy-u2-every-sso-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. No tracker sink was used; this file is the durable record.

## Residual Review Findings

- P3 `db/schema.rb` (`users.password_digest`): the column stays, nullable and unused, now that
  `has_secure_password` and `bcrypt` are gone. Dropping it needs a migration, which wave 1 avoids to
  keep `db/schema.rb` merges trivial. Drop it in a later unit or a follow-up.
- P3 `config/deploy.yml`, `.kamal/secrets` (U14): add `EVERY_OAUTH_CLIENT_ID`,
  `EVERY_OAUTH_CLIENT_SECRET` (secrets), `EVERY_OAUTH_BASE_URL`, and `PUBLIC_BASE_URL` (clear env).
  Without the first three the deployed sign-in page says Sign in with Every is not configured.
- P3 `app/controllers/sessions/every_controller.rb` (`every_person?`): Every's UserInfo
  (`EveryInc/every` `Oauth::UserInfoController`) returns no `email_verified` claim, so the address
  Every returns is trusted and only an explicit `false` is refused. If Every adds the claim, require
  it to be `true`.
- P3 `app/frontend/components/app-nav.tsx` (U10 or U15): there is no sign-out control in the
  navigation yet; `DELETE /session` works and redirects to the sign-in page.
- P3 `test/integration/authentication_gate_test.rb`: the webhook and `/mcp` checks use stand-in
  controllers because those endpoints land in U4, U6, U7, and U12. U15 should assert the real routes
  stay outside the session gate.
