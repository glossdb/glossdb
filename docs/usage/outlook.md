# Forecasts, expected ranges, plans and scenarios

**Status: preview.** These features exist for metrics only. Tables and
single values have none. Forecasts, expected ranges and scenario
estimates need a model service, named once as `GLOSSDB_SERVICE_URL`
([configuration](../reference/configuration.md)). The binary carries
no model. Without the service these measurements are refused by name
and the rest of the server works. A plan reads without the service;
its comparison with the forecast needs it.

Each result is stored as a measurement and read back as SQL.

| Feature | Run | Read | Test |
|---|---|---|---|
| Expected ranges | `SELECT metric_ranges() FROM <dataset>` | `range_points()`, `range_result()` | `range_test` |
| Forecast | `SELECT metric_forecast() FROM <dataset>` | `forecast_points()`, `metric_series(world := 'forecast')` | `forecast_test` |
| Plan | `SELECT metric_plan() FROM <dataset>.<plan>` | `plan_points()`, `metric_series(world := 'plan', plan := '<name>')` | `plan_test` |
| Scenario | `SELECT metric_scenario() FROM <dataset>` | `scenario_points('<name>')`, `scenario_levers('<name>')`, `metric_series(world := 'scenario', scenario := '<name>')` | `scenario_test` |

Where a service is named, `next` lists the measurements that are due
and what they found. The columns of each read:
[reads](../reference/reads.md#the-outlook-kit-preview).

## Expected ranges

`metric_ranges()` backtests each metric's monthly total against its
own history: for each month, the range the earlier months predicted
and where the actual fell. A metric needs seven complete months.
`range_test` reads the service's result. Where the newest month lies
outside its range, `next` names the metric, the value and the range.

```sql
SELECT metric, period, actual, p05, p95 FROM range_points() WHERE newest;
```

## Forecasts

`metric_forecast()` asks the service for each metric at its finest
grain: 31 days, 13 weeks, 12 months or 4 quarters ahead. Metrics at
minute, hour or year grain are not forecast. Each point carries the
quantiles `p05` to `p95`. Once the actuals arrive, `forecast_points()`
shows them beside the forecast, and `forecast_coverage()` counts how
often the ranges held.

```sql
SELECT metric, period, p10, p50, p90, actual FROM forecast_points() WHERE span IS NULL;
```

## Plans

A plan is a budget or a target for one metric. Its numbers are a
loaded table. Declare the plan as a view of its own that names its
metric, and define it with SQL that serves the metric's period and
value columns:

```glossql
DECLARE ASPECT visitor_target WITH $${"title": "Visitor target",
  "x-kind": "plan", "x-plan-of": "visitors"}$$ AS VIEW;
GLOSS visitor_target ON museum AS $${
  "sql": "SELECT month AS visit_date, target AS value FROM targets"
}$$;
```

- `x-plan-of` names the metric. The plan takes the metric's
  additivity; nothing is annotated on the plan's own columns.
- `"x-covers": "year"` or `"quarter"` says each row is booked against
  that period, such as a year's budget booked in January.
- Two editions of a budget are two plans.

```sql
SELECT period, value FROM metric_series(world := 'plan', plan := 'visitor_target')
WHERE dimension = '' ORDER BY period;
```

```sql
SELECT plan, label, value, actual, variance, planned FROM plan_points();
```

`plan_points()` puts each plan beside the actual and, with a service,
the forecast. `planned` says where the plan lies: `complete`,
`inside`, `below` or `above` the forecast's range, `partial`, `open`
or `ahead`. `metric_plan()` stores the comparison; `plan_test` is red
where a period lies outside the range.

## Scenarios

A scenario changes a lever by a factor per period and asks the
service what the metric would do. A lever is a column of a metric's
view that someone sets, such as a price. Annotate it, declare the
scenario, and give the factors:

```glossql
GLOSS lever ON visitors.ticket_price AS $${"value": true, "basis": "set by the board each season"}$$;

DECLARE ASPECT summer_pricing WITH $${"title": "Summer prices up 10%",
  "x-kind": "scenario", "type": "object", "required": ["levers"]}$$ AS FACT ON DATASET;
GLOSS summer_pricing ON museum AS $${"levers": [
  {"column": "visitors.ticket_price", "factor": {"2027-07": 1.1, "2027-08": 1.1},
   "basis": "the price list proposed for the summer"}
]}$$;
```

A period is a month (`YYYY-MM`) or a day. A metric needs 26 periods of
history. `metric_scenario()` stores the estimate;
`scenario_points()` returns it per period with `low`, `value`, `high`
and the service's `sign` and `basis`; `scenario_levers()` returns what
each lever does alone.

```sql
SELECT metric, period, low, value, high, basis FROM scenario_points('summer_pricing');
```
