# Residual review findings: U5 Discord connector

Source run: lfg pipeline for U5 (branch `cursor/happyhappy-u5-discord-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. No tracker sink was used; this file is the durable record.

Applied during review: messages posted inside Discord threads are now routed through the thread's
parent channel (sources select parent channels, and the gateway names only the thread), and the
thread's messages join the starter message's item. Ingest failures on thread messages record the
error on the parent channel's source.

## Residual Review Findings

- P2 `bin/discord`: the gateway loop has not run against Discord. A live smoke run (invite the bot to
  a test server, configure a Discord source for one channel, post a message, a reply, and a thread
  message) is pending a bot token. Unit tests cover the mapping and handlers with recorded payloads.
- P2 `Procfile.dev`: `bin/discord` is not in `Procfile.dev`. Overmind (and the foreman fallback)
  stops every process when one exits, so a token-less `bin/discord` that exits cleanly would stop
  `bin/dev`. Run `bin/discord` in its own terminal locally. Adding it would need `OVERMIND_CAN_DIE`
  support in Copse, or a process that idles instead of exiting.
- P3 `app/services/connectors/discord_bot.rb` (handle_message): a message that fails to ingest (for
  example SQLite busy) is logged and recorded on the source but not retried; the gateway does not
  redeliver. Consider enqueueing ingest as a job if this shows up in source health.
- P3 `app/services/connectors/discord_bot.rb`: discordrb runs each event on its own thread, so a burst
  of messages can briefly exceed the Active Record pool. Size `RAILS_MAX_THREADS` for the discord
  role in U14 if connection timeouts appear.
- P3 `app/services/connectors/discord.rb`: message edits and deletes are ignored, matching the Slack
  connector. Forum posts behave like threads under the forum channel, which must be the configured
  source.
- P3 U14 handoff: the `discord` Kamal role runs `bin/discord` from the same image with
  `DISCORD_BOT_TOKEN` in `.kamal/secrets`, exactly one container. A disconnect during deploy marks
  Discord sources with a gateway error until the new process connects and clears it.
