# Residual review findings: U7 email connector via Postmark

Source run: lfg pipeline for U7 (branch `cursor/happyhappy-u7-email-postmark-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available. One finding was applied (params wrapping turned off on
the webhook so an unauthenticated body is not copied into params). No tracker sink was used; this
file is the durable record.

## Resolved from U1

- U1 P3 `app/models/source.rb` (case-insensitive inbound addresses): decided case-insensitive.
  `Connectors::Postmark` matches recipients with `LOWER(selector)`, so `Help@Cora.Computer` routes
  to the `help@cora.computer` source. `Source` itself is unchanged.

## Residual Review Findings

- P3 `app/models/source.rb`: the selector uniqueness validation is case-sensitive, so two email
  sources `help@x` and `Help@x` can coexist and the connector picks either. U3 (source screens)
  should downcase email selectors on save or validate uniqueness case-insensitively for email.
- P3 `app/services/connectors/postmark.rb`: auto-replies (out-of-office, `Auto-Submitted`
  headers) and bounces are ingested like customer mail. Filtering them is a product call; a
  follow-up could skip mail whose `Auto-Submitted` header is not `no`.
- P3 `app/services/connectors/postmark.rb`: a reply-all from an Every teammate that copies the
  support address is ingested as a customer message on the thread. A follow-up could skip senders
  on the every.to domain.
- P3 `app/services/connectors/postmark.rb`: paused email sources still ingest, the same as U1's
  `Items::Ingest` for every kind. If "paused" should stop ingestion, decide it once in ingest.
- P3 `config/initializers/filter_parameter_logging.rb`: Rails logs request parameters, so inbound
  email bodies (and every other webhook payload) reach the production log. U14 or U15 should decide
  whether to filter webhook body keys such as `TextBody`, `HtmlBody`, and `StrippedTextReply`.
- P3 deploy (U14): `POSTMARK_INBOUND_USER` and `POSTMARK_INBOUND_PASSWORD` must be added to
  `.kamal/secrets` and the web role's secret env in `config/deploy.yml`.
