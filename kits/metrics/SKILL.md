---
name: glossdb-metrics
description: The metrics kit for a glossql workspace — a metric is a view whose columns carry the semantic layer's annotations; the summary row per metric, the series over periods and slices, the refusal when additivity is unknown, the time grains on a time column, single values and sources. Use after glossql_kit('kits/metrics/kit.sql') to define metrics and read their numbers.
---

# The metrics kit: what it teaches

For an actor working in a DuckDB that has the glossql extension loaded,
the KPI kit and the quality kit declared and this kit after them. The
extension serves every metric definition as a view under the metric's
name in the dataset's schema. This kit reads the view's columns as
assets and serves the numbers from what the catalog says about them.
Nothing is marked at read: an annotation older than its data reads
stale, and the reads serve it as the catalog has it.

## Load and check

```sql
FROM glossql_kit('kits/kpi/kit.sql');
FROM glossql_kit('kits/quality/kit.sql');
FROM glossql_kit('kits/metrics/kit.sql');    -- the same three lines in the opener
SELECT * FROM metric_summary();       -- one row per metric: what its columns say
```

## A metric is a view, and its columns are assets

A metric definition is a VIEW gloss on the dataset: SQL under the
contract `sql` or `stopped`, with `assumptions` disclosed. The view it
makes is a table of the dataset, so its columns take the KPI kit's
words, as a loaded table's columns do. What a reader of the numbers
needs is annotated there, never as a key in the definition's body:

| On the view's column | Gloss | What it decides |
|---|---|---|
| the period | `role` = `timestamp` | which column the series walks; serve it as `period` where two columns are timestamps |
| the value | `role` = `measure` | which column is the number; serve it as `value` where two columns are measures |
| the value | `additivity` = `additive`, `semi-additive` or `ratio` (`numerator`, `denominator` naming the halves the view serves) | how the number combines over periods and members: a flow sums, a stock keeps the period's last level, a ratio re-divides its summed halves |
| a slice | `role` = `dimension`, `dimension` = `primary`, `supporting` or `none` | which columns slice the series, primary first; `none` closes one |
| the period | `time_grains` (the time grains) — `floor`, `windows` | the finest grain the series is served at (by default the measured cadence) and how many buckets each grain serves (by default the kit's rungs) |
| the period | `temporal_profile`, a measurement: `SELECT temporal() FROM <dataset>.<metric>.period` | the measured cadence, window, completeness and gaps |

The steps for a new metric: define it; read `metric_summary()`; annotate
what `missing` lists; run what `wanted` lists; annotate `additivity` on the
value; read the series.

```sql
DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;
GLOSS role ON spend.period AS $${"value": "timestamp"}$$;
GLOSS role ON spend.value AS $${"value": "measure"}$$;
GLOSS additivity ON spend.value AS $${"value": "additive", "grounds": "a row is the amount booked in its month"}$$;
GLOSS role ON spend.fund AS $${"value": "dimension"}$$;
SELECT temporal() FROM fin.spend.period;
SELECT * FROM metric_series() WHERE metric = 'spend';
```

## The reads

| Read | Serves |
|---|---|
| `metric_summary()` | one row per metric of the bound dataset: `kind` (the aspect's `x-kind`), `stopped`, `applicable` and `reason` (what to change when it is not applicable), `period_column`, `value_column`, `numerator`, `denominator`, `cadence`, `floor`, `rung`, `additivity` and `additivity_state`, `dims`, `unadmitted` (served columns with no role) and `missing` (the annotation each needs), `wanted` (the measurement nobody ran), `judged_current` |
| `metric_series(grain := …)` | the cells: `metric`, `world`, `dimension` (`''` the total), `member`, `period` (the bucket's start), `value`, `num`, `den`, `additivity`; without a grain each metric at its floor, with one each metric at or below it at that grain, a coarser metric serving no rows; a rung of buckets measured back from the edge; a flow's empty periods zero in the total; a dimension wider than 24 members as its top 23 and `other` |
| `fact_values()` | one row per metric whose aspect carries `x-kind: scalar`: `value` where the view is one row with a `value` column, else `reason` |
| `metric_sources(for_metric := …)` | what feeds each metric, or the one named, through the views' lineage: `field`, `source` (`table.column`), `table_name`; one row per table read beside; a view that does not plan serves `reason` |

## The no-default rule

Where rows have to be combined — a grain coarser than the floor, or
several rows in one period — and the value column has no current
`additivity` annotation, `metric_series()` refuses and names the
annotation to write:

```
no additivity stands on fin.spend.value, and spend serves several rows in one
period: annotate it — GLOSS additivity ON fin.spend.value AS $${"value": "<additive|semi-additive|ratio>"}$$
```

It defaults nothing. A additivity in conflict — the test (`DECLARE TEST`)
withholding the value — refuses the same way, naming the conflict. At
the floor, with one row per period, nothing is combined and the series
serves what the view returns.

## What is not here

A plan, a forecast and a scenario are worlds on the same cells; the
outlook kit (preview) brings them. The additivity evidence a detector
measures on a value column is a measurement of its own; where none was
run, the refusal names the annotation alone.
