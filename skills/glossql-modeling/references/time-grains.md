# Reading a metric: time grains, windows, dimensions

Read when a metric's series, grain or dimensions are not what you
expected, or before you query a metric.

## How a metric is served

A metric is a view. `metric_series()` reads it at query time; nothing
is stored. The annotations on the view's columns say how:

- `role`: `timestamp` marks the period column, `measure` the value
  (the column named `value` where several are measures; `period`
  likewise for timestamps), `dimension` a column to slice by.
- `additivity` on the value column: `additive` sums; `semi-additive`
  keeps the last level of the period; `ratio` divides the summed
  `numerator` by the summed `denominator`.
- `time_grains` on the period column: `floor` is the finest grain
  the series is served at. By default it is the grain `temporal()`
  measured on that column. Where the dates follow no regular grain,
  set it. `windows` is how many whole periods a read returns per
  grain, counted back from the newest data.
- `dimension` ranks a dimension column: `primary` first, then
  `supporting`; `none` leaves it out.

```glossql
GLOSS time_grains ON parcels_delivered.delivered_on AS $${"floor": "month", "windows": {"month": 36}}$$;
```

The grains are `minute`, `hour`, `day`, `week`, `month`, `quarter`
and `year`. The default windows are 1440 minutes, 720 hours, 548
days, 156 weeks, 48 months, 40 quarters and 20 years.

## The series

```sql
SELECT metric, period, value FROM metric_series(grain := 'month')
WHERE dimension = '' ORDER BY metric, period
```

One row per metric, dimension, member and period: `metric`, `world`,
`dimension`, `member`, `period` (the start of the period), `value`,
`num`, `den`, `additivity`.

- `dimension = ''` is the metric's total. A dimension's rows carry
  its column name and one `member` each.
- With a grain, every metric whose floor is that grain or finer is
  served at it; a metric with a coarser floor serves no rows. Without
  a grain, each metric is served at its own floor.
- The metric is a `WHERE` filter, not an argument.
- An additive metric's empty period is a zero, up to the newest date
  any served metric reaches. A semi-additive metric's or a ratio's
  empty period is no row.
- A dimension with more than 24 members serves its top 23 and
  `other`.
- Where rows must be combined and the value column has no
  `additivity`, the read refuses and names the annotation to write.
  `metric_series(unclaimed := 'skip')` serves the other metrics.
- `world` is `actual` unless you ask for a preview feature's numbers
  (`references/preview.md`).

What each metric is served from, and what it still needs:

```sql
SELECT view, applicable, reason, period_column, value_column, additivity, cadence, floor, rung, dims
FROM view_summary() ORDER BY view
```

`applicable` says whether a series can be served, and `reason` what
to change when it cannot.

## Querying a metric yourself

`FROM <metric>` reads the view's rows. Combine them by the metric's
additivity. Additive: sum, and fill a missing period with 0.
Semi-additive: take the last period of each window, do not sum over
time, and leave a missing period empty. Ratio: sum the numerator and
the denominator at the new scope and divide; do not average ratios.
Distinct count: count again at the scope asked.

`lag` and `ROWS` frames count rows, not periods: with a month missing,
`lag(value, 12)` is thirteen months back. Fill the periods first with
`generate_series` (it includes its upper bound), or use a `RANGE`
frame with an interval. `date_trunc('week', d)` starts on Monday. `date_part('month', d)`
folds years together: use it for seasonality, `date_trunc` for
trends. An inner `ORDER BY` does not survive a subquery: order where
you consume. The engine's SQL guide is `doc://vendor/duckdb/sql/…`.
