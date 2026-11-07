---
name: glossdb-futures
description: The futures kit (preview) for a glossql workspace — the worlds beside the actual: expected ranges from a backtest, the forecast, the scenario's estimate and the plan's comparison, each a measurement the model service computes and the catalog serves back. Use after glossql_kit('kits/futures/kit.sql') with a service named, to judge metrics ahead of the data.
---

# The futures kit: what it teaches

This kit is a preview. For an actor working in a DuckDB that has the
glossql extension loaded, the KPI, quality and metrics kits declared and
this kit after them. The metrics kit serves the actual world: the cells
of every metric. This kit adds three worlds beside it: the forecast, the
scenario and the plan. Each is what the model service answers, stored as
a measurement with its provenance (`pin`), and read back as SQL. The
service owns its topic: the bands, the PIT and why it is withheld, the
walk's verdict. The kit owns the calendar and sends complete periods
only. The server's `next` read judges from the catalog and never
computes over the data.

## Load and check

```sql
FROM glossql_kit('kits/kpi/kit.sql');
FROM glossql_kit('kits/quality/kit.sql');
FROM glossql_kit('kits/metrics/kit.sql');
FROM glossql_kit('kits/futures/kit.sql');
SET GLOBAL glossql_service_url = 'http://127.0.0.1:8100';  -- the service, named once for the instance; the server names it from GLOSSDB_SERVICE_URL
SELECT * FROM band_request();                    -- one row per metric: can the walk take it
```

Every call goes through `service(route, body)`, one macro over
`glossql_service`. A test suite replaces the service by re-declaring the
macro. Without a service named, a measurement refuses by name before any
call goes out.

## The worlds

| World | What it is | Read as |
|---|---|---|
| actual | the metrics kit's cells, computed from the view at read | `metric_series()` |
| forecast | the newest forecast's medians at its grain | `metric_series(world := 'forecast')` |
| scenario | the newest estimate's medians ahead, per scenario | `metric_series(world := 'scenario', scenario := '<name>')` |
| plan | a plan's rows through the metric it plans, at the plan's own grain | `metric_series(world := 'plan', plan := '<name>')` |

A world other than these four refuses by name. The actual world is the
only one computed from the data; the others read measurements and the
plan's view.

## The walk: bands

The walk sends every applicable metric's total at month grain, complete
months only, seven at least, so that one origin has the six known values
the service needs. The test's threshold is the red line
the walk is asked with.

```sql
SELECT metric_bands() FROM fin;
SELECT served_by, grain, score, band, threshold FROM band_verdict();
SELECT metric, period, actual, p05, p50, p95, pit, withheld FROM band_points() WHERE metric = 'spend';
```

`metric_bands` stores the service's verdict over every metric walked and,
per metric, whether it was applicable and why not, its behaviour, the
months walked, the share of points inside the 80% and the 90% band, the
newest point and every walked point. The test `bands_w` repeats the
verdict through `band_breach` at 0.98. A metric too short for the walk
serves one row with its reason.

## The forecast

```sql
SELECT metric_forecast() FROM fin;
SELECT step, span, to_go, period, p10, p50, p90, actual, landed, held_80, held_from FROM forecast_points() WHERE metric = 'sales';
SELECT * FROM forecast_coverage();
```

One request per metric at its floor. The horizon is 31 days, 13 weeks,
12 months or 4 quarters; an hour, a minute and a year stay unforecast.
A flow also asks the totals to go: the month, the quarter or the year
the first period ahead falls in. The measurement stores each point as
a step or a span with its band, p05 to p95, and the service's held-out
share at that grain, step and span. No actual is stored with it. The
read joins the actual once it is loaded, says where it fell against the
band (`below`, `low`, `inside`, `high`, `above`) and how often such a
band held: the catalog's own share once thirty points have an actual for
the metric, else for the dataset, else the service's.
`forecast_coverage()` is that tally. The test `forecast_w` says whether
a current forecast exists.

## The scenario

A lever is a FACT on a column of a metric's view: a list price, a
discount rate. Annotate it true where someone sets it, false where it
was looked at and nobody does. A scenario is your own FACT aspect on the
dataset, `x-kind: scenario`, its body a factor per period on declared
levers. A period not named keeps a factor of one.

```sql
DECLARE ASPECT price_up WITH $${"title": "Price +10% in February", "x-kind": "scenario", "type": "object", "required": ["levers"], "properties": {"levers": {"type": "array"}}}$$ AS FACT ON DATASET;
GLOSS lever ON priced.price AS $${"value": true, "grounds": "the list price, set each quarter"}$$;
GLOSS price_up ON fin AS $${"levers": [{"column": "priced.price", "factor": {"2025-02": 1.1}, "basis": "the February price list"}]}$$;
SELECT * FROM scenarios();
SELECT metric_scenario() FROM fin;
SELECT metric, period, low, value, high FROM scenario_points('price_up');
```

`scenarios()` judges every scenario declared: annotated, every lever
an annotated lever on a served metric's column, the factor a map. The
estimate needs 26 periods of history, a period ahead and an input the
scenario moves; a lever held at nothing, or factors of one, is judged
and never sent. The measurement forecasts each lever first and sends
the periods ahead twice, as planned and under the scenario. A lever
whose forecast the service refuses is held at its last value, and the
estimate still holds. Nothing is replayed over the data: the scenario
world is the estimate ahead. `scenario_levers(s)` serves the parts,
what each lever alone does. The test `scenario_w` says whether a
current estimate exists. A new scenario annotation makes the estimate
stale.

## The plan

A plan is a VIEW aspect, `x-kind: plan`, tied to its metric by
`x-plan-of`. Its definition is SQL over a loaded table, serving
`period` and `value` as the metric's view does. The plan serves no cell of the
actual world; its numbers are read under the metric it names.

```sql
DECLARE ASPECT sales_budget WITH $${"title": "Sales budget", "x-kind": "plan", "x-plan-of": "sales"}$$ AS VIEW;
GLOSS sales_budget ON fin AS $${"sql": "SELECT month AS period, planned AS value FROM fin.budget"}$$;
SELECT plan, grain, label, value, actual, variance, low, expected, high, stands FROM plan_points() WHERE plan = 'sales_budget';
SELECT metric_plan() FROM fin.sales_budget;
```

`plan_points()` judges every served plan against the actual and the
newest forecast, one row per period at the plan's own grain and, where
that is finer, at the year: the plan's cell, the actual to date, the
variance on a complete period, the forecast's 80% band, and `stands`:
`landed`, `inside`, `below`, `above`, `partial`, `open` or `ahead`.
`metric_plan` stores that judgement on the plan with the forecast run
it was judged against. The plan's row asks for it until a current one
exists; it goes stale once the data or the catalog rows it read change.
`plan_record()` is the newest judgement from the measurements alone,
the read the `next` step for the plan takes. The test `plan_w` names
the gap.

## The reads

| Read | Serves |
|---|---|
| `band_request()`, `band_body()` | the walk's request per metric, and the body as the service's contract spells it |
| `band_verdict()`, `band_points()` | the newest walk: its verdict; one row per metric and walked month |
| `forecast_request()`, `forecast_bodies()` | the forecast's request per metric, and one body per grain and set of totals |
| `forecast_points()`, `forecast_runs()`, `forecast_record()`, `forecast_coverage()` | the newest run flattened with the actual joined; every run; every run's points; the tally of how bands held |
| `scenarios()`, `scenario_request()`, `scenario_bodies()`, `lever_bodies()` | every scenario judged; its reach per metric; the what-if bodies; the levers' own forecast requests |
| `scenario_points(s)`, `scenario_levers(s)` | the newest estimate per scenario, metric and period ahead; the parts per lever |
| `plan_rows()`, `plan_grains()`, `plan_cells(at_grain)` | every applicable plan's rows through its metric; its grain; its cells at a grain |
| `plan_points()`, `plan_record()` | the plans judged at read; the newest judgement from the catalog |
| `world_cells(w, p, s, g)` | the forecast, scenario and plan worlds under the metric, for `metric_series(world := …)` |

## The goals

`routes_futures()` answers two goals for the server's `next` read.
Bands: a current walk exists and no band is red. Plan: the plan served,
the forecast at the current origin, the plan judged against it, every
gap judged by a person, with a scenario's estimate where one is
annotated. Every step reads the catalog, none the data.

## What is not here

The model is the service's: the bands, the PIT, the verdict, the
estimate. An hour, a minute and a year are not forecast. No metric
definition is replayed over the data under a scenario.
