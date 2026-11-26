# Anomaly detection: fewer allocations per scan

`Anomalies::Detect` runs every 15 minutes (hourly windows) and once a day (calendar days). On a seeded
database it was the most expensive backend path measured, and most of its cost was building points for
windows with no messages. `Anomalies::Series` now builds points only for windows that have messages.

## Why this path

One scan or request, seeded SQLite database (21,200 items, 46,035 messages, 818 anomalies):

| Path | SQL queries | SQLite VM steps | Allocated objects |
|---|---|---|---|
| Anomaly scan, day | 52 | 1,501,010 | 4,475,520 |
| Anomaly scan, hour | 22 | 458,317 | 4,244,839 |
| Mood dashboard, 7d | 13 | 236,579 | 75,713 |
| Mood dashboard, 24h | 13 | 53,522 | 25,899 |
| Product overview | 20 | 84,306 | 22,495 |
| Items feed, by actionability | 16 | 291,200 | 11,449 |
| Items feed | 16 | 11,011 | 11,181 |
| Classification apply | 17 | 451 | 3,305 |
| Ingest (`Items::Ingest`, one message) | 14 | 148 | 2,862 |

VM steps cover SELECTs only. The table shows the cost of one run; how often viewers load pages was not measured.

In the hourly scan, building lines took about 4.06M of 4.27M allocations: 1,216 lines of 216 windows each,
with 84% of the product and source windows empty.

## Result

Median of 3 interleaved pairs (before, after, before, ...), 1-minute load 8 to 10. Allocations were the same
in all three runs of each side.

| Metric | Before | After | Change |
|---|---|---|---|
| Objects per hourly scan | 4,244,820 | 402,998 | -90.5% |
| Objects per daily scan | 4,475,471 | 2,943,842 | -34.2% |
| Objects per day (96 hourly + 1 daily) | 411,978,191 | 41,631,650 | -89.9% |
| SQL queries, hourly / daily | 22 / 52 | 22 / 52 | none |
| CPU per hourly scan (secondary) | 408 ms | 106 ms | -74% |
| CPU per daily scan (secondary) | 812 ms | 706 ms | -13% |

Held-out database (different random seed, 15,200 items), 3 interleaved pairs: 398,790,662 to 33,337,698
objects per day (-91.6%), queries unchanged at 44 / 58. Selection never used it; it was run only for this final
confirmation, not before each kept change.

## Kept changes

Objects per day after each, on the selection database, against the state before it:

1. Share one set of blank points for windows with no messages: 411,978,191 to 57,475,534.
2. Keep the blank point when a category has no messages in an occupied window: 57,475,534 to 46,774,494. This
   number comes from a run that also included change 1.
3. Group each window's customers by mood once, instead of once per mood: 46,774,494 to 41,631,650.

The keep threshold was a 5% cut of objects per day. Skipping detector training when the lift is under the
minimum cut the daily scan by 30% (3.23M to 2.27M) but only 2.3% of the primary, so it was reverted.

## Behavior

Output was compared with the original code by digest, on both databases: every point of every line, and every
`DetectedAnomaly` and `Incident` row and enqueued job after a scan, for both granularities, at two times, starting
from existing and from empty anomalies. All digests matched. An empty-series shortcut failed the same check.
One internal difference: points for empty windows are shared between lines, and their `item_ids` is frozen. The
only caller, `Detect`, does not modify it.

## How it was measured

The harness is not in the repository. Each run set the clock to a fixed time, ran `GC.start`, and read
`GC.stat(:total_allocated_objects)` around `Anomalies::Detect.call(granularity:, now:)` in a rolled-back
transaction, three times, keeping the median. To repeat the core number against any database:

```sh
bin/rails runner 'now = Time.current
%w[hour day].each do |g|
  GC.start; before = GC.stat(:total_allocated_objects)
  ActiveRecord::Base.transaction { Anomalies::Detect.call(granularity: g, now: now); raise ActiveRecord::Rollback }
  puts "#{g}: #{GC.stat(:total_allocated_objects) - before}"
end'
```

Run it only on a disposable local database: a scan may enqueue jobs even though its rows are rolled back.

## Remaining opportunities

- The scan's message query reads every item (`SCAN items`) because `messages.occurred_at` has no index. An index
  needs a migration, so it was out of scope and is unmeasured.
- The reverted training change, worth about 30% of the daily scan.
- `home/index` polls `scene` and `today` every 30 seconds, and the controller still builds `anomalies` on those
  partial reloads. Cost not attributed.
