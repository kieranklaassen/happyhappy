# Residual review findings: U6 Intercom connector

Source run: lfg pipeline for U6 (branch `cursor/happyhappy-u6-intercom-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. Simplify applied no changes. Review produced no findings
eligible for apply; the items below are downstream. No tracker sink was used; this file is the
durable record.

## Residual Review Findings

- P3 `app/services/connectors/intercom.rb` (`inbound_message`): Intercom has no user handle, so
  Intercom items carry `author_name` and `author_email` but a nil `author_handle`. U13's escalation
  message (R29, "the customer's handle") should fall back to name, then email.
- P3 `config/initializers/filter_parameter_logging.rb`: Rails logs webhook JSON as request
  parameters. `email` is already filtered, but message bodies are logged on every Intercom delivery.
  Filtering `body` app-wide touches a shared initializer, so it is left to the owner or U15.
- P3 `app/services/connectors/intercom.rb`: the connector never fetches a conversation, because both
  handled topics carry the customer's message in the notification. The plan's `Intercom-Version: 2.16`
  header applies only if a later change adds a fetch (for example if Intercom trims parts).
- P3 `app/services/connectors/intercom.rb` (`permalink`): the inbox URL shape
  `https://app.intercom.com/a/inbox/<app_id>/inbox/conversation/<id>` matches U1's fixture; confirm
  it opens the conversation in Every's workspace during the U14 smoke run.
