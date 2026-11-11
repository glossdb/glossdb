---
name: glossdb-outlook
description: The outlook kit (preview) for a DuckDB with the glossql extension — expected ranges, forecasts, scenarios and plans for metrics, each computed with a model service, stored as a measurement and read back as rows. Use after glossql_kit('kits/outlook/kit.sql') with a model service configured.
---

# The outlook kit (preview)

For work in a DuckDB that has the glossql extension loaded, with the
kpi, quality and views kits and this kit after them. The views kit
serves each metric's actual values. This kit adds numbers a model
service computes: expected ranges, a forecast and a scenario's
estimate. It also compares a plan with the actual and the forecast.
Each result is stored as a measurement and read back with SQL. Every
feature here is in preview. How to use each one, with a working
example: `skills/glossql-modeling/references/preview.md`.

```sql
FROM glossql_kit('kits/kpi/kit.sql');
FROM glossql_kit('kits/quality/kit.sql');
FROM glossql_kit('kits/views/kit.sql');
FROM glossql_kit('kits/outlook/kit.sql');
SET GLOBAL glossql_service_url = 'http://127.0.0.1:8100';  -- the server sets it from GLOSSDB_SERVICE_URL
SELECT * FROM range_request();
```

Every call goes through the macro `service(path, body)`; a test suite
replaces the service by declaring the macro again. With no service
configured, a call is refused: the engine says `no service is named`,
and the server names its own setting, `GLOSSDB_SERVICE_URL`. Where no
metric qualifies, no call goes out and the function stores a reason
per metric; its test then has no result, and is never green.

| Feature | Run | Needs | Test | Reads |
|---|---|---|---|---|
| expected ranges | `SELECT metric_ranges() FROM <dataset>` | seven complete months | `range_test`, detector `range_breach` at 0.98 | `range_request()`, `range_body()`, `range_result()`, `range_points()` |
| forecast | `SELECT metric_forecast() FROM <dataset>` | six periods; day, week, month or quarter grain | `forecast_test`: a stored result holds a point | `forecast_request()`, `forecast_bodies()`, `forecast_points()`, `forecast_runs()`, `forecast_scored()`, `forecast_stored()`, `forecast_coverage()` |
| scenario | `SELECT metric_scenario() FROM <dataset>` | 26 periods; a period after the last complete one; a factor other than 1 | `scenario_test`: a stored result holds a point | `scenarios()`, `scenario_request()`, `scenario_bodies()`, `lever_bodies()`, `scenario_points(s)`, `scenario_levers(s)` |
| plan | `SELECT metric_plan() FROM <dataset>.<plan>` | a plan view with a definition; a stored forecast for the ranges | `plan_test`: red where a period lies outside the forecast's 80% range | `plan_rows()`, `plan_grains()`, `plan_cells(at_grain)`, `plan_points()`, `plan_stored()` |

The `…_request()` reads say per metric whether a call would go out
and why not. Each function reads `complete_series()`: the metric's
series inside its window, 48 months by default, without a last period
the data ends inside (`partial_periods()`). The expected ranges cover
the latest six months; `backtested` counts the months tested.
`forecast_scored()` is one point per metric, origin and step, from
the newest run; `forecast_coverage()` tallies those. `plan_points()`
reads `not_covered` where the series does not cover a period the plan
has. `scenario_points()` carries `baseline`, the same estimate with
every lever as planned, and `effect`, the value minus it.

`metric_series()` takes `world`: `actual` (the default), `forecast`,
`scenario` (with `scenario := '<name>'`) or `plan` (with `plan :=
'<name>'`); another value is refused. `world_cells(w, p, s, g)` is the
read behind the three that are not `actual`.

`outlook_measurements()` names the functions a dataset needs where a
model service is configured, with `stored` and `due`: the expected
ranges, the forecast once a plan is served or a scenario can be
estimated, the scenario estimate once a scenario can be estimated.
Each function stores `inputs`, a digest of what its request read
(`outlook_inputs()`, `view_inputs()`): the metrics' SQL, columns,
grain and additivity and the newest load of each table they scan,
and for a scenario its levers and factors. `outlook_due()` says a
result is due when none is stored, or when the catalog marks it stale
and the digest differs. The server's `next` lists the ones that are
due. `outlook_findings()` adds rows to `next`: a value outside its
expected range, a plan's year outside the forecast's range, a plan
not compared since the newest forecast or its own change, a plan
without a definition, a scenario its author can fix. A finding stated
as an assumption (`range-<period>`, `plan-<year>`) leaves the list.
`preview_tests()` serves the four tests as rows of `view_tests()`,
per metric, with the state `not_applicable` where a result holds no
point and nothing can be done about it. Each of these reads the
catalog, not the data.
