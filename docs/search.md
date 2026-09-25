# Feed search

The search box on the feed and the `search_items` agent tool search items and
their messages in plain language, through the [truffler](https://github.com/kieranklaassen/truffler)
gem (0.1.2). Both go through `FeedSearch`, so people and agents get the same
results for the same query and filters.

## How a search runs

1. **Keystroke.** Every pause in typing reloads the feed with `q`. No Jev call
   happens here: the query's encoding is read from the cache, and on a miss it
   is enqueued (one Jev call) while the feed shows full-text matches from the
   SQLite FTS5 index (`item_search_documents`: author fields and every message
   body, prefix and stemmed). The page reloads itself until the encoding lands.
2. **Chips.** Once Jev has read the query, labels it names become chips:
   a filter (only items with that label) or a boost (ranked higher). Under a
   label filter, words only rank; they are not required in the text. A time
   phrase ("today", "yesterday", "this week", "last month", "last 3 hours",
   "past week", "past month", "past 2 weeks", "since monday") is read by
   truffler without Jev, limits `last_message_at`, and shows as the last chip.
   "past week" and "past month" end now; "this/last week" and "this/last
   month" are calendar windows. Removing a chip searches again without it.
   The feed filters above always apply too.
3. **Smart search (Enter).** Jev reads the top 30 candidates and sorts them
   into Strong, Possible, and Unlikely (collapsed). Buckets fill in as each
   chunk of 10 is read: `TrufflerChannel` pings the searcher and the page
   reloads only its `smart` prop. Any query or chip change cancels the run.
   Each person gets 10 Smart runs a minute (truffler's per-user cap).
4. **Lenses.** Any signed-in person may create app-wide or personal lenses
   (`config.lenses`); nothing in the UI creates them yet.

Agents call `search_items` (read-only) with a `query`, the `list_items`
filters, and `removed_chips`. It waits up to 2 seconds for the encoding, then
answers with chips and items whose customer text is marked untrusted.

## Labels

Truffler stores one row per label per item. Labels classification already
answers are **supplied** from the item's columns (`from:`), so they cost
nothing and Jev is never asked them twice. A watched column change rewrites
the label after commit.

| Label | Kind | Source |
|---|---|---|
| sentiment | supplied | `items.sentiment` |
| product | supplied | the item's product slug, or `none` once classified |
| category | supplied | the item's category name, or `other` once classified |
| anger | supplied | `items.anger_probability` |
| needs_action | supplied | `items.actionability` (filters at the should-reply threshold) |
| status | supplied | `items.status` |
| source | supplied | `items.source_kind` |
| team_replied | supplied | a team member wrote in the thread |
| needs_review | supplied | `items.needs_review` |
| churn_risk | **asked** | Jev reads the conversation |

`churn_risk` is the only asked label: classification has nothing like it, and
a customer about to leave hides as easily in a bug report or a billing
question as under a cancellation category. It is asked when an item arrives
and again when its conversation changes (a new message), in batches of 10
items per call.

The dashboard mood is not a label: it is derived from sentiment and anger,
and Jev reading "angry" as both the anger label and a mood filtered on two
contradictory answers.

Relevance is not a label either: search runs inside `ItemsQuery`, which hides
not-relevant items unless the Relevance filter says otherwise.

## Deploy

The first deploy runs three migrations: truffler's tables, the FTS5 index
(filled from existing items and messages inside the migration), and
truffler's backfill spend ledger (`truffler_backfill_spends`, added with
`bin/rails generate truffler:upgrade` in 0.1.2).

```bash
bin/rails db:migrate
bin/rails search:reindex                                 # free: every supplied label, no Jev call
bin/rails "truffler:status[Item]"                        # counts by status
bin/rails "truffler:backfill[Item]"                      # paid: churn_risk for existing items
```

The backfill asks only `churn_risk` (supplied labels never reach Jev). At
truffler's default price (`config.cost_per_million_tokens`, 0.042 dollars)
20,000 items with long threads cost about a dollar. Spend stops at truffler's
default `config.backfill_spend_cap` (5 dollars) per vocabulary version, across
reruns and automatic `BackfillJob` chains: the ledger reserves each request's
estimate before it is sent, and `truffler:status` shows the spend so far.
`SPEND_CAP=<dollars>` (checked against the ledger total, not the run) or
`SPEND_CAP=none` overrides the cap, `RESET_SPEND=1` zeroes the ledger, and `MAX_DURATION=<seconds>` pauses the run
(budget denials are waited out, not fatal). Run it only when Kieran approves the spend. Until then, items have every supplied
label and `churn_risk` fills in for new and updated items.

No new environment variables. Truffler uses `TYPESAFE_API_KEY` and counts its
calls against `TYPESAFE_REQUESTS_PER_MINUTE`, keeping half the limit free for
classification (`config.headroom = 0.5`). Its jobs run on the `default` queue;
`config/recurring.yml` schedules `ResumeJob` (every 5 minutes),
`PruneQueryMissesJob`, and `ExpireLensesJob` (daily).

When a supplied label's `from:` logic changes, bump its `version:` in
`Item::Searchable` and run `bin/rails search:reindex`. Changing `config.model`
marks `churn_risk` stale for the paid backfill.

## Development

```bash
bin/rails search:demo      # mood:demo plus billing, Thesis, and urgent items over a few weeks
```

Then try "angry Cora billing this week", "needs action now", and "praise for
Thesis". Query encoding and Smart search need `TYPESAFE_API_KEY`; without it
the feed search is full-text only.

Measure with `script/latency/search.sh` (see `script/latency/README.md`).

## Notes on truffler 0.1.2

- **`none` and `other`.** `product_options` and `category_options` always
  offer them: they are answers `from:` gives, and the option set is part of
  every stored product and category label's fingerprint.
