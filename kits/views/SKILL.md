---
name: glossdb-views
description: The views kit for a DuckDB with the glossql extension — a view is named SQL on a dataset (a table, a single value or a metric); the annotations on a metric's columns say how its series is served; the summary row per view, the series, single values, lineage and the built-in tests. Use after glossql_kit('kits/views/kit.sql') to define views and read them.
---

# The views kit

For work in a DuckDB that has the glossql extension loaded, with the
extension's kpi and quality kits and this kit after them. The
extension serves each view definition as a view under its name in
the dataset's schema. This kit reads the annotations on the view's
columns and serves the numbers from them. Defining and reading views
in full: `skills/glossql-modeling/references/define.md` and
`time-grains.md`.

A view is a `VIEW` aspect defined on the dataset with `sql` or
`stopped`. Its `x-kind` says what it serves: `relation` a table,
`scalar` a single value, none a metric. A metric's columns carry the
annotations the series is served from:

| On the view's column | Annotation | Decides |
|---|---|---|
| the period | `role` = `timestamp` | which column the series runs over; name it `period` where two columns are timestamps |
| the value | `role` = `measure` | which column is the number; name it `value` where two columns are measures |
| the value | `additivity` = `additive`, `semi-additive`, `ratio` (with `numerator`, `denominator`) or `non-additive` | how rows combine over periods and members |
| a slice | `role` = `dimension`; `dimension` = `primary`, `supporting` or `none` | which columns slice the series, in which order |
| the period | `time_grains`: `floor`, `windows` | the finest grain served (by default the measured one), and the periods a read returns per grain |

```sql
FROM glossql_kit('kits/kpi/kit.sql');
FROM glossql_kit('kits/quality/kit.sql');
FROM glossql_kit('kits/views/kit.sql');
DECLARE ASPECT parcels WITH $${"title": "Parcels delivered"}$$ AS VIEW;
GLOSS parcels ON logistics AS $${"sql": "SELECT date_trunc('month', delivered_on)::DATE AS period, sum(parcels) AS value, depot_id FROM logistics.deliveries GROUP BY 1, 3"}$$;
GLOSS role ON parcels.period AS $${"value": "timestamp"}$$;
GLOSS role ON parcels.value AS $${"value": "measure"}$$;
GLOSS additivity ON parcels.value AS $${"value": "additive", "basis": "a row is the parcels delivered in its month"}$$;
GLOSS role ON parcels.depot_id AS $${"value": "dimension"}$$;
SELECT temporal() FROM logistics.parcels.period;
SELECT * FROM view_summary();
SELECT * FROM metric_series() WHERE metric = 'parcels';
```

| Read | Gives |
|---|---|
| `view_summary()` | one row per view: `kind`, `stopped`, `applicable` and `reason` (what to change when no series can be served), `period_column`, `value_column`, `numerator`, `denominator`, `cadence`, `floor`, `rung`, `additivity`, `additivity_state`, `dims`, `unranked`, `unadmitted` (columns with no role), `missing` (the annotation each needs), `wanted` (a measurement to run), `judged_current` |
| `metric_series(grain := …)` | the series: `metric`, `world`, `dimension` (`''` is the total), `member`, `period`, `value`, `num`, `den`, `additivity` |
| `fact_values()` | one row per single value: `value` where the view is one row with a column `value`, else `reason` |
| `view_sources(for_view := …)` | lineage: per view and field the source `table.column`, and one row per table read |
| `view_tests()` | per view, the tests on it and on what it reads, worst first |
| `semantic_model()`, `lineage_events()` | the dataset as an Ossie document; its lineage as OpenLineage events |

Additivity is not defaulted. Where rows have to be combined and the
value column has no current `additivity`, or one in conflict,
`metric_series()` refuses and names the annotation to write.

Four tests apply to each metric: `fan_out_test`, `orphan_test`,
`validity_test` and `measure_additivity_test`. Each is a measurement
over the metric, `SELECT <check>() FROM <dataset>.<metric>`, whose
`breach_rate` the detector `rate_tolerance` scores; 0 is green. Its
result carries a `finding` and a `fix`. A tolerance annotated on the
metric at or above the rate accepts the result. A test the team
declares on a view, or on a column of it, is listed with that view.
