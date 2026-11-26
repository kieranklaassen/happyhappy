# Mood dashboard poll: compute only what it sends

The dashboard reloads `scene` and `today` every 30 seconds and after each live change. It also computed
`anomalies` and `options`, loaded message bodies for people it does not draw, and read every item column.
It now runs 5 queries instead of 12 and allocates 28 to 32% fewer objects per poll, with the same JSON.

## Result

Seeded SQLite database: 21,000 items, 51,075 messages, 125 active anomalies, 814 relevant items in 24 hours and
3,494 in 7 days (the scene reads at most 2,000). Median of 5 requests per run, 3 interleaved pairs (before, after,
before, ...), 1-minute load 12 to 14 after each pair. The three runs of each side gave the same numbers.

| Request | Objects | SQL queries | SQLite VM steps |
|---|---|---|---|
| Poll, 7d | 98,728 to 67,401 (-31.7%) | 12 to 5 | 344,158 to 90,361 |
| Poll, 24h | 48,985 to 35,156 (-28.2%) | 12 to 5 | 145,231 to 59,836 |
| Poll, 7d, one product | 58,545 to 35,395 (-39.5%) | 13 to 6 | 302,251 to 93,032 |
| Full page, 7d | 98,769 to 73,232 (-25.9%) | 12 to 12 | 344,158 to 95,033 |
| Full page, 24h | 49,026 to 40,987 (-16.4%) | 12 to 12 | 145,231 to 64,508 |
| Feed poll (`items,anomalies`) | 18,161 to 17,495 (-3.7%) | 19 to 16 | 14,671 to 13,891 |
| Feed full page | 18,259 to 18,265 | 19 to 19 | 14,671 to 14,671 |

Held-out database (different seed; 9,000 items, 22,113 messages, 42 active anomalies), same protocol, load 12 to 15:

| Request | Objects | SQL queries | SQLite VM steps |
|---|---|---|---|
| Poll, 7d | 74,218 to 53,225 (-28.3%) | 11 to 5 | 249,887 to 77,572 |
| Poll, 24h | 25,916 to 20,138 (-22.3%) | 11 to 5 | 62,543 to 39,331 |
| Full page, 7d | 74,259 to 56,529 (-23.9%) | 11 to 11 | 249,887 to 79,545 |
| Full page, 24h | 25,957 to 23,442 (-9.7%) | 11 to 11 | 62,543 to 41,304 |
| Feed poll | 10,833 to 10,167 (-6.1%) | 15 to 12 | 11,984 to 11,204 |

Those pairs compare the commit this branch started from with the branch. After main was merged in, one pair per
database against the new main gave the same poll numbers. It also measured search reloads of the feed (one pair,
same on both databases): `smart` alone, 1,839 to 1,172 objects and 4 queries to 1; `items,search`, 6,433 to 5,859
objects and 8 queries to 7. Query counts leave out query cache hits.

## Kept changes

Objects for one 7d poll plus one 24h poll, each against the state before it, one run per change (keep threshold 2%):

1. Pass the dashboard props as lambdas, so a partial reload runs only the ones it asks for: 147,713 to 136,171,
   and 24 queries to 10.
2. Load message bodies only for drawn people: 136,171 to 124,813, VM steps 480,045 to 226,175.
3. Compute a person's seed only when drawn: 124,813 to 116,593.
4. Select only the item columns the scene reads: 116,593 to 102,557. The load rose above 20 during this run; the
   final pairs confirmed it.
5. Build the feed's `options` in a lambda. This does not change the dashboard numbers.

## Behavior

The response bodies of 497 requests were hashed before and after on four databases (two more than the two above, both
past the 2,000-item limit), and all matched. They cover 9 dashboard URLs with full loads, every prop alone, every prop
left out, every pair, and `only` with `except`; 8 feed URLs with full loads, every prop alone and left out, and the
combinations the page uses; and product overviews. No prop is deferred in this app. Replacing every excerpt with a
constant made 108 of the 497 fail, so the check notices changes.

A reload that names a key inside a lambda prop (`only: today.mood`) now sends the whole prop. Nothing in the app does this.

Limits: the seeds have no search index rows and no Smart run, so in search requests `items` was empty and `smart` was
null. The test suite covers those.

## How it was measured

The harness is not in the repository. It drove requests through an integration session with a fixed clock, a fixed asset
version, and a signed-in user, warmed each request 4 times, then read `GC.stat(:total_allocated_objects)` around it with
GC off. Queries and VM steps (`SQLite3::Statement#stat(:vm_steps)`) came from a separate pass. It was run as
`DATABASE_URL=sqlite3:<scratch>.sqlite3 RAILS_ENV=test bin/rails runner measure.rb` in a copy of each side.
Wall time was not used. To repeat the core number on a disposable local database with at least one user session and items
from the last day:

```sh
RAILS_ENV=test DATABASE_URL=sqlite3:/path/to/scratch.sqlite3 bin/rails runner '
require "action_dispatch/testing/integration"
InertiaRails.configure { |c| c.version = "v" }
s = ActionDispatch::Integration::Session.new(Rails.application); s.host! "localhost"
jar = ActionDispatch::TestRequest.create.cookie_jar; jar.signed[:session_id] = Session.first.id
s.cookies["session_id"] = jar[:session_id]
headers = { "X-Inertia" => "true", "X-Inertia-Version" => "v", "X-Inertia-Partial-Component" => "home/index",
            "X-Inertia-Partial-Data" => "scene,today" }
%w[7d 24h].each do |range|
  4.times { s.get "/?range=#{range}", headers: headers }
  queries = 0
  GC.start; before = GC.stat(:total_allocated_objects)
  s.get "/?range=#{range}", headers: headers
  objects = GC.stat(:total_allocated_objects) - before
  count = ->(*, payload) { queries += 1 unless payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name]) }
  ActiveSupport::Notifications.subscribed(count, "sql.active_record") { s.get "/?range=#{range}", headers: headers }
  puts "#{range}: #{s.response.status} #{objects} objects, #{queries} queries"
end'
```

## Remaining opportunities

- Active anomalies of category volume look up their category one at a time (`DetectedAnomaly#label`). That likely explains most of
  the feed poll's 26 query cache hits; it was not attributed. Not changed.
- Product overviews have no partial reload, so the same pattern does not apply. The page's largest cost is reading
  `created_at` and sentiment for 30 days of items (40,457 objects for 3,459 items, outside a request).
- The scene still builds one record per item. Reading plain rows instead was not tried.
- No index was tried, since migrations were out of scope.
