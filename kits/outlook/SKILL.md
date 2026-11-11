---
name: glossdb-outlook
description: The outlook kit (preview) for a DuckDB with the glossql extension — expected ranges, forecasts, scenarios and plans for metrics, each computed by a model service, stored as a measurement and read back as rows. Use after glossql_kit('kits/outlook/kit.sql') with a model service configured.
---

# The outlook kit (preview)

For work in a DuckDB that has the glossql extension loaded, with the
kpi, quality and views kits and this kit after them. The views kit
serves each metric's actual values. This kit adds numbers a model
service computes: expected ranges, a forecast, a scenario's estimate
and a plan's comparison. Each is stored as a measurement with the
versions of the data it read and read back with SQL. Every feature
here is in preview. How to use each one:
`skills/glossql-modeling/references/preview.md`.

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
configured, a measurement refuses and says so before a call goes out.
The kit sends complete periods only.

| Feature | Run | Test | Reads |
|---|---|---|---|
| expected ranges | `SELECT metric_ranges() FROM <dataset>` | `range_test`, detector `range_breach` at 0.98 | `range_request()`, `range_body()`, `range_result()`, `range_points()` |
| forecast | `SELECT metric_forecast() FROM <dataset>` | `forecast_test`: a current forecast exists | `forecast_request()`, `forecast_bodies()`, `forecast_points()`, `forecast_runs()`, `forecast_stored()`, `forecast_coverage()` |
| scenario | `SELECT metric_scenario() FROM <dataset>` | `scenario_test`: a current estimate exists | `scenarios()`, `scenario_request()`, `scenario_bodies()`, `lever_bodies()`, `scenario_points(s)`, `scenario_levers(s)` |
| plan | `SELECT metric_plan() FROM <dataset>.<plan>` | `plan_test`: the plan against the forecast's range | `plan_rows()`, `plan_grains()`, `plan_cells(at_grain)`, `plan_points()`, `plan_stored()` |

`metric_series()` takes `world`: `actual` (the default), `forecast`,
`scenario` (with `scenario := '<name>'`) or `plan` (with `plan :=
'<name>'`); another value is refused. `world_cells(w, p, s, g)` is the
read behind the three that are not `actual`.

`outlook_findings()` adds this kit's rows to the server's `next`
where a model service is configured: a value outside its expected
range, a plan outside the forecast's range, a plan not yet compared
with the newest forecast, a plan without a definition.
`outlook_measurements()` names the measurements a dataset needs;
`next` lists the ones that are due. Each row reads the catalog, not
the data.
