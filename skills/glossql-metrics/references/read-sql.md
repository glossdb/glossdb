# Querying a metric — read before any query over a metric: how each kind adds up, and what DuckDB has that postgres lacks

The engine is DuckDB. Names are case-insensitive, quoted or not. A
column loaded with capitals keeps that spelling in listings. Quote a
name that is a reserved word. The MCP interface runs queries; DDL, DML
and COPY are refused. More: `skill://glossql/references/sql-here.md`.

## Query at the grain you need

A metric definition is a view under the metric's name: `FROM
<metric>`. It is the current definition, and a person's outranks the
agent's. One definition answers by month and by day.

- **Additive: sum** over any grouping.
- **Semi-additive: take the last period per window**,
  `last_value(value ORDER BY ts)` as an aggregate, ORDER BY required.
  Never sum it over time, and never ROLLUP it across time. A
  period-over-period difference is fine.
- **Ratio: divide again.** Sum the numerator and the denominator at
  the new scope and divide. Never average finer ratios, and never
  regroup a ratio's output rows.
- **Distinct count: count again.** Distinct customers per region do
  not sum to distinct customers. Run `count(DISTINCT …)` at the scope
  asked.
- **Missing periods.** For an additive metric, coalesce to 0. For a
  semi-additive one, leave it: a missing level is unknown, not zero.
- **`lag` and ROWS frames count rows, not periods.** With a month
  missing, `lag(value, 12)` is thirteen months ago. Fill the periods
  first, or use a RANGE frame with an interval.

Percentiles and medians are safe for every kind. Use p50 and p95 when
`additivity` is not annotated.

## DuckDB, not postgres

DuckDB has tools postgres lacks. Do not write a self-join per
comparison or a subquery per rank. The engine's guide for this release
is served at `doc://vendor/duckdb/sql/…`, functions under
`functions/`.

**One scan, many answers.** Declare the window once and reuse it.
`FILTER (WHERE …)` turns one member into a column without a self-join.
WHERE removes rows from every aggregate, FILTER from one. An empty
filter gives COUNT 0 but SUM and AVG NULL, so coalesce before
dividing.

```sql
SELECT period, driver, value,
  value - lag(value) OVER w                     AS delta,
  sum(value) OVER (PARTITION BY period)         AS period_total,
  value / sum(value) OVER (PARTITION BY period) AS share,
  avg(value) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma3,
  sum(value) FILTER (WHERE driver = 'EMEA') OVER (PARTITION BY period) AS emea
FROM series
WINDOW w AS (PARTITION BY driver ORDER BY period)
```

**`QUALIFY` filters on a window result**: top-N per period with no
subquery. It runs after windows, before ORDER BY and LIMIT. Give the
ORDER BY a full tiebreaker, or `row_number` changes between runs.
`ntile` splits by row count, not by value. For the top decile by
value use the cumulative share: `sum(value) OVER (ORDER BY value DESC)
/ sum(value) OVER ()`.

```sql
SELECT period, site, value FROM completions
QUALIFY rank() OVER (PARTITION BY period ORDER BY value DESC, site) <= 10
```

**Fill the periods before you lag.** `generate_series` is a table
function and includes its upper bound; `range` excludes it. The
coalesce is for an additive metric; a semi-additive one keeps its
NULLs.

```sql
SELECT months.m AS period, coalesce(b.value, 0) AS value
FROM generate_series(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1' MONTH) AS months(m)
LEFT JOIN monthly b ON b.period = months.m
```

Or use a frame over values. **RANGE accepts intervals**: the last
three calendar months, whatever is missing.

```sql
SELECT period, avg(value) OVER (ORDER BY period
  RANGE BETWEEN INTERVAL '2' MONTH PRECEDING AND CURRENT ROW) AS smoothed
FROM monthly
```

Two frame defaults to know:

- With an ORDER BY and no frame, the frame is `UNBOUNDED PRECEDING AND
  CURRENT ROW` including ties, so tied rows share a running total.
  Order by a column that is unique at the grain.
- Under that default, the window function `last_value` returns the
  current row, not the partition's last. Use the aggregate form above.

For year over year with periods missing, use a self-join: `ON
prev.period = cur.period - INTERVAL '1 year'`.

**Group by the annotated dimensions.** These are the served columns
with `role` dimension, ranked by the `dimension` annotation, primary
first.

- A column most rows leave empty makes a top-N describe a minority.
  One dominant value makes ranks and ntiles useless.
- ROLLUP follows the declared hierarchy, coarse to fine:
  `ROLLUP(region, country, city)`. Reversed, the subtotals are wrong.
- Subtotal rows carry NULL in the rolled-up columns, and so does a
  real NULL member. Test `grouping(col)`, never `IS NULL`.
- `GROUP BY ALL` is for exploring. A stored metric definition spells
  its GROUP BY, because ALL regroups when someone edits the select
  list.

**Time.**

- `date_trunc` to the metric's grain and no finer. `'week'` starts on
  ISO Monday.
- `time_bucket(interval, d, origin)` for fiscal periods and offset
  weeks; the fiscal calendar's start goes in the origin.
- `date_part('month', d)` folds years together. Use it for
  seasonality, `date_trunc` for trends.
- `dow` is Sunday = 0, `isodow` Monday = 1.

**Statistics.**

- `quantile_cont(v, 0.95)` is exact. `approx_quantile(v, 0.95)`
  scales; never compare approximate values across runs as a trend.
- `regr_slope(value, epoch(period))` per member finds declining
  segments. Aggregate to the grain first. `value` comes first;
  swapped arguments give a wrong number, not an error. The slope is
  per second, so scale it.
- `stddev(value) / nullif(avg(value), 0)` ranks volatility.
- `approx_count_distinct` counts active members at scale.
- `corr` needs both series on the same periods: fill or join first.
- `list(x ORDER BY period)`: a `list` without ORDER BY has no fixed
  order.

**Store a query you verified.** A query you checked can be stored as
the metric's definition and is then served as the view `throughput`.
Build on `FROM throughput` where you can, so a review decision on one
metric reaches every metric built on it.
