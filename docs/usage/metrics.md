# Metrics

A metric is a `VIEW` property: SQL with its assumptions, served as a
view under the metric's name. Annotations on the view's columns make it
a series: which column is the period, which the value, which the
slices, and how the value adds up. The signatures of the metric views
are in [views and table functions](../reference/reads.md).

## Define a metric

Declare one property per concept, and keep its declaration thin: a
`title` and the `x-kind` flag. What the company revises (meaning, unit,
owner, source, a formula) goes in the `definitions` annotation, where a
correction replaces the entry with its author and time.

```glossql
DECLARE ASPECT throughput WITH $${"title": "Throughput", "x-kind": "measure"}$$ AS VIEW;
GLOSS definitions ON ops AS $${"definitions": {
  "throughput": {"meaning": "work completed and accepted; counted at completion date",
                 "unit": "hours", "owner": "Operations", "source": "KPI handbook v3 §2"}
}}$$;
GLOSS throughput ON ops AS $${
  "sql": "-- completed work: hours per closed order, at completion date, with its judged axes\nSELECT w.completed_at AS date, w.duration_min / 60.0 AS value, s.region, s.service_line FROM work_orders w JOIN sites s ON w.site_id = s.id WHERE w.status = 'closed'",
  "assumptions": [
    {"dimension": "scope", "key": "closed-only", "assumption": "closed orders only; cancelled and reopened excluded", "basis": "status values + judgment", "confidence": 0.7},
    {"dimension": "additivity", "key": "throughput-is-a-flow", "assumption": "a flow: sums valid over any partition", "basis": "minutes per visit, one row per visit", "confidence": 1.0}
  ]
}$$;
```

- **Write the SQL at row grain,** with no `GROUP BY`: one row per
  event, with a period column, a `value` column and the columns to
  slice by. The series views aggregate it to any grain.
- **Put mechanics in SQL comments,** where they cannot drift from the
  query, and judgment in `assumptions`.
- **Give every assumption a `key`.** It is the claim's identity; an
  assumption below full confidence with a key becomes a question in the
  [review queue](review.md).
- **Preview first.** Run the SQL with `LIMIT 0` before you record it.
- **`definitions` is one annotation for the whole dataset,** so a write
  replaces the whole map. Read the current entries before you add one.
- **A level is a stock.** Payables outstanding, inventory, headcount:
  anything you could state as of any date. Collapse the events to one
  row per entity per period, and annotate `additivity` stock on the value.

A metric is a view of the dataset: `SELECT … FROM <name>` reads,
filters and joins it like any view. A person's definition outranks the
agent's, so a person's correction is what runs:

```sql
SELECT date_trunc('month', date) AS month, sum(value) AS hours
FROM throughput GROUP BY date_trunc('month', date)
ORDER BY month
```

The write answers with the metric's summary row, in the
`metric_summary()` shape: whether the SQL plans, the period and value
columns, the additivity, the cadence, the slices admitted, and every
column still missing an annotation. Read it before the next write.

## Three other kinds of view

The same `VIEW` property serves three other things, told apart by
`x-kind` in the declaration:

| `x-kind` | What it is | Served as |
|---|---|---|
| `measure` | a metric: a series over time | the series views, the console's charts |
| `scalar` | a single value with no date, such as a balance the source hands over already summed | `FROM <name>`, `fact_values()`, the console's single values |
| `relation` | shared SQL other definitions build on: a cleaned join, a scoped subset | `FROM <name>`; a change to it reaches every definition that reads it |

A single value given a date becomes a one-point series. A validation
is not a metric: it is a [data test](data-tests.md).

## Make it a series

Annotate the view's columns:

- `role` timestamp on the period column, `role` measure on the value
  column (the one named `value` where several are measures), `role`
  dimension on each column to slice by;
- `additivity` on the value column: `additive` (a flow) sums, `semi-additive` (a stock) keeps each
  bucket's last level, `ratio` divides its summed halves, named by
  `numerator` and `denominator`;
- `dimension` on a slice column to rank it: `primary` first, `none`
  closes it.

Then run `temporal()` over the period column. Its measured cadence is
the grain the series is served at by default. The `time_grains` annotation
on the period column sets the time grains instead: `floor`, the finest
grain served, and `windows`, how many whole buckets a read serves per
grain, counted back from the data's newest point.

```glossql
GLOSS time_grains ON throughput.date AS $${"floor": "month", "windows": {"month": 120}}$$;
```

Check what the catalog says of each metric's columns:

```sql
SELECT metric, applicable, reason, additivity, cadence, floor, rung, dims, unadmitted, missing
FROM metric_summary() ORDER BY metric
```

## Read the series

```sql
SELECT metric, period, value FROM metric_series(grain := 'month')
WHERE dimension = '' ORDER BY metric, period
```

`metric_series()` serves every applicable metric at the asked grain,
one row per metric, dimension, member and period. `dimension = ''` is
the metric's total.

- Without a grain, each metric is served at its own floor. A metric
  coarser than the asked grain serves no rows.
- A flow's empty period is a zero up to the data's newest point. A
  stock's or a ratio's empty period has no row.
- Where rows have to be combined and the value column has no
  `additivity`, the read refuses and names the missing annotation; it
  assumes nothing. `unclaimed := 'skip'` serves the other metrics.
- A dimension with more than 24 members serves its top 23 by weight
  and `other`. `other` is not a business member; serve a narrower
  column from the metric's SQL if you need one.
- A distinct count or a ratio serves no slices, since no column slices
  it whole.

`metric_surfaces` lists every metric with its title, unit, meaning and
formula.

## Formulas

A derived metric's `formula` in `definitions` defines it over sibling
metrics, for any window `w`: `[w]` reads a flow over the window,
`[end of w]` a stock at its end, `[w-1]` the previous window. The
formula documents the metric; the stored SQL is what runs. Formulas
are not checked, so read the operand names back against
`SELECT name FROM aspects WHERE kind = 'VIEW'`.

## Stop a metric

A metric the data cannot support is recorded as stopped: `stopped`
with the reason in place of `sql`. The console shows the reason beside
the name, and the `metrics` goal counts it as done.
