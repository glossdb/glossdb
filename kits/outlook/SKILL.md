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
configured, a call is refused with `no service is named`. Where no
metric qualifies, no call goes out and the function stores a reason
per metric.

| Feature | Run | Needs | Test | Reads |
|---|---|---|---|---|
| expected ranges | `SELECT metric_ranges() FROM <dataset>` | seven complete months | `range_test`, detector `range_breach` at 0.98 | `range_request()`, `range_body()`, `range_result()`, `range_points()` |
| forecast | `SELECT metric_forecast() FROM <dataset>` | six periods; day, week, month or quarter grain | `forecast_test`: a result is stored | `forecast_request()`, `forecast_bodies()`, `forecast_points()`, `forecast_runs()`, `forecast_stored()`, `forecast_coverage()` |
| scenario | `SELECT metric_scenario() FROM <dataset>` | 26 periods; a period after the last actual; a factor other than 1 | `scenario_test`: a result is stored | `scenarios()`, `scenario_request()`, `scenario_bodies()`, `lever_bodies()`, `scenario_points(s)`, `scenario_levers(s)` |
| plan | `SELECT metric_plan() FROM <dataset>.<plan>` | a plan view with a definition; a stored forecast for the ranges | `plan_test`: red where a period lies outside the forecast's 80% range | `plan_rows()`, `plan_grains()`, `plan_cells(at_grain)`, `plan_points()`, `plan_stored()` |

The `…_request()` reads say per metric whether a call would go out
and why not. Each function reads `metric_series()` inside the
metric's window, 48 months by default. The expected ranges cover the
latest six months and leave out a month the data ends inside.

`metric_series()` takes `world`: `actual` (the default), `forecast`,
`scenario` (with `scenario := '<name>'`) or `plan` (with `plan :=
'<name>'`); another value is refused. `world_cells(w, p, s, g)` is the
read behind the three that are not `actual`.

`outlook_measurements()` names the functions a dataset needs where a
model service is configured: the expected ranges, the forecast once a
plan is served, the scenario estimate once a scenario is annotated.
The server's `next` lists the ones that are due: not run yet, or
older than the data or a definition. `outlook_findings()` adds rows
to `next`: a value outside its expected range, a plan's year outside
the forecast's range, a plan not yet compared with the newest
forecast, a plan without a definition. A finding stated as an
assumption (`range-<period>`, `plan-<year>`) leaves the list. Each
row reads the catalog, not the data.
