# The shipped function library

Declared by the kits at every open. A function's body rides its
declaration, so the whole library reads back as worked examples:

```sql
SELECT name, script FROM functions;
```

A **measurement** RETURNS an aspect: run it with `SELECT <name>() FROM
<subject>` and the result lands as a measurement row recording what it
read — it serves, and stays current, while those inputs are unchanged;
the full value reads back via `GLOSSARY(<subject>::<aspect>)`. When a
measurement cannot speak it returns `applicable: false` with a
`reason` — an abstention is a complete answer, never an error. A
**detector** has no RETURNS: it is named by a witness's `DETECTOR`
clause, sees only the slots written under that aspect, and answers a
band and a score.

Measurements propose; they never verdict. The judge — the agent
reading them — removes false positives.

A column's evidence is owed by role: the profile on every column,
`temporal` where `role = 'timestamp'`. Owed is not gated: any
measurement still runs on any column on ask, and lands.

## Column grain

### column_profile → `column_profile`

`SELECT column_profile() FROM <table>.<column>`. The deterministic
profile: counts, null ratio, distinct and cardinality ratio, min and
max, top values, string lengths, and for numeric columns mean, stddev,
MAD and percentiles. Measures the landed table — the recipe carried
the casts, so `null_ratio` counts the cells the author's casts nulled.

### outlier_profile → `outlier_profile`

`SELECT outlier_profile() FROM <table>.<column>`. IQR fences (1.5×IQR)
and the modified Z-score (|0.6745·(x − median)/MAD| > 3.5) —
distribution facts with no domain rule. Abstains on a column that
does not parse as numbers (`applicable: false`); a MAD of 0 makes
every deviation infinite, so the Z-score arm counts zero and the IQR
fences stand alone.

### temporal → `temporal_profile`

`SELECT temporal() FROM <table>.<column>`, and over a metric's period
column, `SELECT temporal() FROM <metric>.<column>`. Window, cadence,
completeness, gaps. Cadence is the named grain nearest the median gap
between distinct instants; completeness counts calendar buckets over
the column's own window; a gap is a stretch beyond twice the median,
the twenty largest sampled. A point in time bounds a window; a number
or a text does not, and the reason names the type. The cadence is the
floor a metric's ladder defaults to ([reads](reads.md),
`metric_axes()`).

## Table grain

### detect_hierarchies → `hierarchy_candidates`

`SELECT detect_hierarchies() FROM <table>`. Functional dependencies
between a table's columns, one row per screened direction: `g3` the
share of rows that break from → to, `g3_reverse` the other way,
`gk_lambda` for predicting `to` from `from`, `rows_per_value` the
evidence per value. Measures stay out by type; a column distinct on
every filled row is out, since it determines everything; NULL is a
category. Candidates ship at g3 ≤ 0.05; a near-copy both ways at
g3 ≤ 0.01 is kind `alias` — whether that is a code↔label relabeling or
a coincidence is what no statistic settles. λ rides beside every
candidate, never gated.

### detect_derivations → `derivation_candidates`

`SELECT detect_derivations() FROM <table>`. Row-grain arithmetic
identities among numeric columns — `a = b·c` and `a = b+c` — with
support, violation count and match rate. An identity holds at match
rate ≥ 0.95 over ≥ 20 supporting rows. A confirmed identity re-checked
per landing is the admission instrument for subtle corruption: a
scoped artifact violates the lineage identity at exactly its row
coverage while every marginal statistic confuses it with a real
business move ([derivations](../methods/derivations.md)).

## Dataset grain

### detect_relationships → `relationship_candidates`

`SELECT detect_relationships() FROM <dataset>`. Every plausible join
pair across the landed tables, by value containment — generous by
design; the judge removes false positives against the data. Per
candidate: endpoints, cardinality, overlap, matched and orphan counts,
distinct counts; a composite endpoint rides `key_columns` (the tuple
is the key). Ranked clean keys first, then many-to-one, then overlap,
then key coverage; the order demotes and never drops
([discovery](../methods/discovery.md)).

### relationship_coherence → `relationship_coherence`

`SELECT relationship_coherence() FROM <dataset>`. What each DECLARED
join asserts, checked against the rows: filled count, orphan count and
rate, and child-before-parent date incoherence per temporal column
pair, the first three date columns of each side. A relationship
within one table is checked as a dependency: its orphans are the rows
whose finer value maps to more than one coarser value, and it carries
no temporal pair ([coherence](../methods/coherence.md)).

### detect_grounding_collisions → `grounding_collisions`

`SELECT detect_grounding_collisions() FROM <dataset>`. Metrics that
are the same thing twice: groundings whose SQL is the same statement
once parsed, case and spacing aside, under different aspects; and
groundings whose monthly series agree over every month though their
SQL differs, each folded by its behaviour. Reported, never resolved:
deliberate synonyms exist, and telling them from errors is the judge's
call against the definitions.

### metric_bands → `metric_bands`

`SELECT metric_bands() FROM <dataset>`. For every applicable metric,
walks the six most recent complete months and asks the model service
what range each month should have landed in given everything before
it. Each walked point records the band quantiles (p05–p95) and its
PIT, the quantile at which the actual landed; the walk records the
service's verdict, score, band and threshold, over every metric
walked. A metric with fewer than seven complete months is inapplicable
before any call ([bands](../methods/bands.md)).

### metric_forecast → `metric_forecast`

`SELECT metric_forecast() FROM <dataset>`. For every applicable
metric, asks the model service for the periods ahead from the last
period with a value: the band quantiles (p05–p95) per step over a
horizon fixed per grain — day 31, week 13, month 12, quarter 4 — and
for a flow the totals of the month, quarter or year to go. The run
lands with its origin and `served_by`, and with each point the
service's held-out share inside the 80% and the 90% band at that
grain, step and span. `forecast_points()` joins the actuals as they
land and `forecast_coverage()` counts the coverage ([reads](reads.md),
[forecast](../methods/forecast.md)). A metric finer than day, coarser
than quarter, or shorter than six periods is inapplicable with the
reason; one the service cannot forecast is inapplicable in the
service's words.

### metric_scenario → `metric_scenario`

`SELECT metric_scenario() FROM <dataset>`. For every scenario glossed,
the estimate of every metric a lever reaches: each lever forecast on
its own as the planned input, then the what-if route's quantiles
under the scenario, its sign, confidence and basis, and per lever what
it alone does by the history. `scenario_points()` and
`scenario_levers()` read it back ([scenario](../methods/scenario.md)).

## Plan grain

### metric_plan → `metric_plan`

`SELECT metric_plan() FROM <dataset>.<plan>`. The plan judged against
the actual and the forecast: the rows `plan_points()` serves for it,
landed with the forecast run they were judged against. Owed on a
served plan until one stands; the plan goal asks for it again once a
newer forecast stands ([plan](../methods/plan.md)).

## Detectors

### slot_entropy

Bound by the KPI kit to `role_w`, `behavior_w`, `unit_w` (threshold
0.7). Score is the fraction of extra distinct values across the
aspect's slots — 0.0 when every voice agrees. Band: green at 0, yellow
up to the threshold, red above it.

### band_breach

Bound by the futures kit to `bands_w` on `metric_bands` (threshold
0.98). Repeats the service's verdict over the walk — the worst
displacement, |2·PIT − 1|, across the newest point of every metric
walked, raised to the number of metrics scored — as the band and the
score, so that `ATTEST()` carries it and the checks goal routes on it.
Which metric and which month live in the measurement's own output;
`band_points()` serves them as rows ([reads](reads.md)).

### forecast_stands, scenario_stands

Bound to `forecast_w` and `scenario_w`: green once a run has landed,
so that the forecast and the estimate are owed while none has, and
owed again once stale.

### plan_gap

Bound to `plan_w` on `metric_plan`: red where a banded period of the
judgement lies below or above the forecast's band, the score the
share of banded periods that do.
