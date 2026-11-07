# Functions

The functions the kits declare at every open. A function's body is
stored with its declaration, so the library reads back as worked
examples:

```sql
SELECT name, script FROM functions;
```

There are two kinds:

- A **measurement** returns an aspect. Run it with `SELECT <name>()
  FROM <asset>`. The result is stored with the versions of what it
  read, and served again while those are unchanged. The full value
  reads back with `GLOSSARY(<asset>::<aspect>)`. A measurement that
  does not apply returns `applicable: false` with a `reason`: a
  complete answer, not an error.
- A **detector** returns no aspect. A test names it in its `DETECTOR`
  clause. It sees only the values written for that aspect and returns a
  band and a score.

Measurements propose; they never decide. The agent reading them
removes the false positives.

Each column is expected to carry some measurements, by its role: the
profile on every column, `temporal` where `role = 'timestamp'`,
`behavior_evidence` where `role = 'measure'`. Any measurement still
runs on any column when asked.

## Column measurements

### column_profile

`SELECT column_profile() FROM <table>.<column>` → `column_profile`

Counts, null ratio, distinct count and cardinality ratio, min and max,
top values, string lengths, and for numeric columns mean, standard
deviation, MAD and percentiles. It measures the loaded table, so
`null_ratio` counts the cells the load query's casts set to NULL.

### outlier_profile

`SELECT outlier_profile() FROM <table>.<column>` → `outlier_profile`

IQR fences (1.5 × IQR) and the modified Z-score (|0.6745 · (x −
median) / MAD| > 3.5). Not applicable to a column that does not parse
as numbers. A MAD of 0 makes every deviation infinite, so the Z-score
counts zero and the IQR fences stand alone.

### temporal

`SELECT temporal() FROM <table>.<column>`, or over a metric's period
column `SELECT temporal() FROM <metric>.<column>` → `temporal_profile`

Window, cadence, completeness and gaps. Cadence is the named grain
nearest the median gap between distinct instants. Completeness counts
calendar buckets over the column's own window. A gap is a stretch
longer than twice the median; the twenty largest are sampled. Only a
date or timestamp has a window; for a number or text the reason names
the type. The cadence is the default finest grain of a metric's series
([views and table functions](reads.md), `metric_axes()`).

## Table measurements

### detect_hierarchies

`SELECT detect_hierarchies() FROM <table>` → `hierarchy_candidates`

Functional dependencies between a table's columns, one row per
direction screened: `g3` the share of rows that break from → to,
`g3_reverse` the other way, `gk_lambda` for predicting `to` from
`from`, `rows_per_value` the evidence per value. Measures are left out
by type. A column distinct on every filled row is left out, since it
determines everything. NULL counts as a category. Candidates have
g3 ≤ 0.05; a near-copy both ways at g3 ≤ 0.01 is kind `alias`. λ is
reported beside every candidate, never used as a filter.

### detect_derivations

`SELECT detect_derivations() FROM <table>` → `derivation_candidates`

Row-level identities among numeric columns, `a = b·c` and `a = b+c`,
with support, violation count and match rate. An identity holds at a
match rate ≥ 0.95 over ≥ 20 supporting rows. An identity checked again
on every load catches subtle corruption: a damaged slice breaks the
identity on exactly its rows, while every summary statistic mistakes
it for a real business change ([derivations](../methods/derivations.md)).

### behavior_evidence

`SELECT behavior_evidence() FROM <table>.<column>` → `behavior_evidence`

Whether a numeric column is a stock (a level at a point in time) or a
flow (a movement that sums over a period). A column's own values
cannot decide it. The evidence is a movement summed per entity and
period from an event table that the declared relationships connect to
the column's table, scored against both readings: flow where the level
matches the movement, stock where its change does. The summary carries
the verdict, the event table and alignment that decided, its
convention, the Wilson support over the entities both sides share, the
voted count, the median residuals of both readings and the sign split.
Every candidate reads back through
`GLOSSARY(<table>.<column>::behavior_evidence)`, with the reasons for
those that did not apply. A table with no declared relationship to an
event table, no time column, or a column that is not a number is not
applicable. It never annotates `behavior` itself: the agent reads the
evidence, then annotates ([behavior](../methods/behavior.md)).

## Dataset measurements

### detect_relationships

`SELECT detect_relationships() FROM <dataset>` → `relationship_candidates`

Every plausible join pair across the loaded tables, by value
containment. Generous by design; the agent removes the false
positives against the data. Per candidate: endpoints, cardinality,
overlap, matched and orphan counts, distinct counts; a composite key is
in `key_columns`. Ranked clean keys first, then many-to-one, then
overlap, then key coverage. The order demotes and never drops
([discovery](../methods/discovery.md)).

### relationship_coherence

`SELECT relationship_coherence() FROM <dataset>` → `relationship_coherence`

What each declared relationship claims, checked against the rows:
filled count, orphan count and rate, and child-before-parent date
conflicts for each pair of date columns, the first three of each side.
A relationship within one table is checked as a dependency: its
orphans are the rows whose finer value maps to more than one coarser
value, and it has no date pairs ([coherence](../methods/coherence.md)).

### detect_grounding_collisions

`SELECT detect_grounding_collisions() FROM <dataset>` → `grounding_collisions`

Metrics that are the same thing twice: definitions whose SQL is the
same statement once parsed, under different names; and definitions
whose monthly series agree in every month though their SQL differs,
each combined by its additivity. Reported, never resolved: synonyms can
be deliberate, and telling them from mistakes is the agent's call.

## Preview measurements

These call the model service the deployment names
([preview](../preview/forecasts.md)).

### metric_bands

`SELECT metric_bands() FROM <dataset>` → `metric_bands`

For every applicable metric, walks the six most recent complete months
and asks the model service what range each month should have landed in
given everything before it. Each point records the band quantiles
(p05–p95) and its PIT, the quantile the actual landed at; the walk
records the service's verdict, score, band and threshold. A metric with
fewer than seven complete months is not applicable
([expected ranges](../preview/expected-ranges.md)).

### metric_forecast

`SELECT metric_forecast() FROM <dataset>` → `metric_forecast`

For every applicable metric, the periods ahead from the last period
with a value: the band quantiles (p05–p95) per step over a horizon per
grain (day 31, week 13, month 12, quarter 4), and for a flow the
totals of the month, quarter or year to go. The run is stored with its
origin and `served_by`, and each point with the service's held-out
share inside the 80% and 90% band at that grain, step and span.
`forecast_points()` joins the actuals as they arrive and
`forecast_coverage()` counts the coverage. A metric finer than day,
coarser than quarter, or shorter than six periods is not applicable
([forecasts](../preview/forecasts.md)).

### metric_scenario

`SELECT metric_scenario() FROM <dataset>` → `metric_scenario`

For every scenario annotated, the estimate of every metric a lever
reaches: each lever forecast alone as the planned input, then the
what-if quantiles under the scenario, its sign, confidence and basis,
and per lever what it alone does by the history. `scenario_points()`
and `scenario_levers()` read it back ([scenarios](../preview/scenarios.md)).

### metric_plan

`SELECT metric_plan() FROM <dataset>.<plan>` → `metric_plan`

The plan compared with the actual and the forecast: the rows
`plan_points()` serves for it, stored with the forecast run they were
compared against. Expected on a served plan until one exists, and
again once a newer forecast exists ([plans](../preview/plans.md)).

## Detectors

### slot_entropy

Used by the KPI kit's tests `role_test`, `behavior_test` and `unit_test`
(threshold 0.7). The score is the share of extra distinct values among
the values for the aspect: 0.0 when all agree. Green at 0, yellow up
to the threshold, red above it.

### rate_tolerance

Bands a written expectation against a computed breach rate on the same
aspect: green at or under the tolerance. One-sided; a source that must
also catch over-cleaning declares its own detector
([data tests](../usage/data-tests.md)).

### band_breach

Used by the outlook kit's test `bands_test` on `metric_bands` (threshold
0.98). Repeats the service's verdict over the walk: the worst
displacement, |2·PIT − 1|, across the newest point of every metric
walked, raised to the number of metrics scored. `TESTS()` carries it
and the `checks` goal acts on it. Which metric and month is in the
measurement's own output; `band_points()` returns them as rows.

### forecast_exists, scenario_exists

Used by `forecast_test` and `scenario_test`: green once a run exists, so a
forecast and an estimate are expected while none exists, and again
once they go stale.

### plan_gap

Used by `plan_test` on `metric_plan`: red where a period with a band lies
below or above the forecast's band; the score is the share of such
periods.
