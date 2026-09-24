# Residual review findings: U14 Kamal deploy on Hetzner

Source run: lfg pipeline for U14 (branch `cursor/happyhappy-u14-kamal-deploy-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Config only; nothing was deployed.
Simplify and code review ran inline because no subagents were available. No tracker sink was used;
this file is the durable record.

## Residual Review Findings

- P2 `bin/discord` with `config/deploy.yml` (`discord` role): the bot exits 0 when
  `DISCORD_BOT_TOKEN` is empty, so Kamal fails the `discord` role on deploy. That is loud by design;
  `DEPLOYING.md` documents `bin/kamal deploy --roles web` for shipping before the bot exists.
- P3 `config/deploy.yml` (`discord` role): Kamal starts the new `discord` container before stopping
  the old one, so two gateway sessions can overlap for a few seconds. Duplicate deliveries dedupe on
  the message id; U5 already clears the gateway error when the new process connects.
- P3 `config/deploy.yml`: `RAILS_MAX_THREADS` is not set for the `discord` role (U5 handoff). Add a
  role-level `env.clear` if connection pool timeouts appear under message bursts.
- P3 `config/initializers/filter_parameter_logging.rb` (U6, U7 handoff to U14 or U15): webhook bodies
  (`TextBody`, `HtmlBody`, `StrippedTextReply`, Intercom `body`) still reach the production log.
  Left to U15 because the initializer is shared and not in U14's file list.
- P3 `.kamal/secrets`: an unset provider variable reaches the container as an empty string rather
  than failing the deploy; each feature then refuses requests or stays off. Kamal's dotenv parsing
  has no required-variable syntax, so the render-time `KeyError` covers only `deploy.yml` values.
- P3 `.kamal/secrets`: the template's Riffrec comment names `RIFFREC_API_KEY` but no line passes it
  through and `deploy.yml` does not list it. Pre-existing template state; left unchanged.
- P3 `.env.example`: `SLACK_BOT_TOKEN` and `PUBLIC_BASE_URL` each appear twice after the Wave 1 merges.
  Harmless; left so sibling merges stay trivial.
- P3 `docs/modules/deploy.md`: the template module doc still describes a single `web` role. The app
  runbook is `DEPLOYING.md`; the module doc was left as template text.

## Deviation

- `PUBLIC_BASE_URL`, `EVERY_OAUTH_BASE_URL`, and `APP_TIME_ZONE` are rendered as `env.clear` from the
  deploy environment instead of `env.secret`. The first two use `ENV.fetch` with no default so a
  missing value fails the render; an empty `APP_TIME_ZONE` secret would have crashed boot
  (`config.time_zone = ""`), so it defaults to `UTC` at render time. None of the three is a secret.
