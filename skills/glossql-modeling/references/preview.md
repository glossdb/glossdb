# Preview features: expected ranges, forecasts, plans, scenarios

These features are in preview. They apply to metrics only and need a
model service configured on the server; without one, each function
refuses and says so. Label what you hand out from them as preview.
Each is a function you run on the dataset. The result is stored and
read back as rows. `next` lists a function when it is due and adds
its findings.

## Expected ranges

`SELECT metric_ranges() FROM <dataset>` asks, per metric and recent
month: given the months before, what range would this month fall in?
It sends complete months only; a metric needs at least seven.

```sql
SELECT metric, period, actual, p05, p50, p95, pit, withheld FROM range_points()
WHERE newest ORDER BY displacement DESC
```

`pit` says where the actual fell in the range: 0.5 is the middle,
above 0.95 or below 0.05 is outside what the history explains.
`range_result()` is the run in one row; the test `range_test` carries
each metric's newest month. A shift in the business and a defect in
the data look the same here. Fix a defect in the load or the
definition. Tell a person about a shift: state it as an assumption
with the key `range-<period>` in the metric's definition.

## Forecasts

`SELECT metric_forecast() FROM <dataset>` asks for the periods after
the last one with a value: 31 days, 13 weeks, 12 months or 4
quarters, by the metric's floor. Minutes, hours and years are not
forecast. An additive metric also gets the totals to the end of the
month, the quarter and the year. It is due again after each load.

```sql
SELECT metric, step, period, p10, p50, p90, actual, held_80, held_from FROM forecast_points()
```

`actual` fills in as the periods arrive. `held_80` says how often
such a range held, and `held_from` whose count that is: this metric's
own once 30 of its points have arrived at that step, otherwise the
dataset's, otherwise the service's share on held-out data. Hand a
range out with it. `metric_series(world := 'forecast')` serves the
medians beside the actuals; `forecast_coverage()` counts how often
actuals fell inside the ranges.

## Plans

A plan (a budget, a target) is a loaded table. Declare one view per
plan, and per edition of it, with `x-kind: plan` and `x-plan-of`, the
metric it plans:

```glossql
DECLARE ASPECT parcels_target WITH $${"title": "Parcels target 2026", "x-kind": "plan", "x-plan-of": "parcels_delivered"}$$ AS VIEW;
GLOSS parcels_target ON logistics AS $${"sql": "SELECT month AS period, target AS value FROM targets"}$$;
```

The plan's period and value columns carry the names of the metric's,
or `period` and `value`. Its additivity is the metric's, and its
columns are not annotated. A row covers its own period; where one row
holds the whole year, add `"x-covers": "year"` to the declaration.
`metric_series(world := 'plan', plan := 'parcels_target')` serves the
plan under its metric's name, at the plan's grain or coarser; a
variance is a join of that read and the actuals on `metric` and
`period`.

```sql
SELECT plan, grain, period, value, actual, variance, low, expected, high, planned FROM plan_points()
```

`plan_points()` compares each plan with the actual and the newest
forecast, per period and at the year. `planned` is `complete`,
`inside`, `below` or `above` the forecast's 80% range, `partial`,
`open` or `ahead`. `SELECT metric_plan() FROM <dataset>.<plan>`
stores the comparison; the test `plan_test` reads it. For a year
outside the range, state the gap as an assumption with the key
`plan-<year>` in the plan's definition.

## Scenarios

A lever is a column of a metric's view that someone sets, such as a
price. A scenario changes levers by a factor per period (`YYYY-MM`
or `YYYY-MM-DD`; a period not named keeps 1) and asks what the
metrics would do.

```glossql
GLOSS lever ON parcel_revenue.price_per_parcel AS $${"value": true, "basis": "the tariff, set each January"}$$;
DECLARE ASPECT tariff_up WITH $${"title": "Tariff +5% from March", "x-kind": "scenario", "type": "object",
  "required": ["levers"], "properties": {"levers": {"type": "array"}}}$$ AS FACT ON DATASET;
GLOSS tariff_up ON logistics AS $${"levers": [{"column": "parcel_revenue.price_per_parcel", "factor": {"2027-03": 1.05}, "basis": "the tariff proposal"}]}$$;
SELECT metric_scenario() FROM logistics;
```

```sql
SELECT metric, period, low, value, high, held_80, held_from, sign, confidence FROM scenario_points('tariff_up')
```

`scenarios()` checks each scenario. The estimate needs 26 periods of
history and a lever the scenario moves. No definition is run again
over changed data: the result is an estimate for the periods ahead.
`metric_series(world := 'scenario', scenario := 'tariff_up')` serves
the medians; `scenario_levers('tariff_up')` gives each lever's part.
Interactions between levers are not estimated. Hand an estimate out
with its range and `held_80`.
