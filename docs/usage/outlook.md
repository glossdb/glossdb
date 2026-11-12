# Forecasts, expected ranges, plans and scenarios

**Status: preview.** These features exist for metrics only. Tables and
single values have none. Expected ranges, forecasts and scenarios are
computed by a model service, named once as `GLOSSDB_SERVICE_URL`
([configuration](../reference/configuration.md)). The binary carries
no model. A plan reads without the service; its comparison with the
forecast needs a stored forecast.

Each feature is a function you run on the dataset. The result is
stored as a measurement and read back as SQL.

| Feature | Run | Read | Test |
|---|---|---|---|
| Expected ranges | `SELECT metric_ranges() FROM <dataset>` | `range_points()`, `range_result()` | `range_test` |
| Forecast | `SELECT metric_forecast() FROM <dataset>` | `forecast_points()`, `forecast_coverage()`, `metric_series(world := 'forecast')` | `forecast_test` |
| Plan | `SELECT metric_plan() FROM <dataset>.<plan>` | `plan_points()`, `metric_series(world := 'plan', plan := '<name>')` | `plan_test` |
| Scenario | `SELECT metric_scenario() FROM <dataset>` | `scenario_points('<name>')`, `scenario_levers('<name>')`, `metric_series(world := 'scenario', scenario := '<name>')` | `scenario_test` |

The columns of each read:
[reads](../reference/reads.md#the-outlook-kit-preview). The four tests
are rows of `TESTS(<dataset>)` and `TESTS(<dataset>.<plan>)`, and of
`view_tests()` under the metric: a plan's test shows under the metric
it plans.

The examples are from one run against a model service: New York
subway service per month. The metric `trains_run` is the trains that
ran, with the actuals loaded through August 2025. The timetable is
loaded through August 2026. Each call took 2 to 6 seconds for this
one metric with the service on the same machine (measured).

## When each one is due

Where a service is named, `next` lists what is due, each row with
the statement to run:

- `metric_ranges` once a metric is served.
- `metric_forecast` once a plan has a definition or a scenario can be
  estimated: the plan is held against the forecast's ranges, and the
  scenario reads how often they held. It runs without either too;
  `next` does not list it then.
- `metric_scenario` once a scenario is annotated and its levers hold.
- `metric_plan` once per plan, and again after each new forecast or a
  change to the plan.

The server does not run them itself. A stored result is due again
when something it reads changed:

| Result | Due again after |
|---|---|
| expected ranges, forecast | a load of a table a metric scans; a change to a metric's SQL, its time or value column, its grain or its additivity |
| scenario estimate | the same for the metrics its levers are on; a change to a scenario's levers or factors |
| plan comparison | a new forecast; a change to the plan's SQL or a load of its table |

Other changes leave them as they are: another view, a new plan, an
assumption added to a definition, an annotation the series does not
read. `TESTS()` reads `current = false` after any change to the
catalog; `next` and `outlook_measurements()` list a function only
when it is due. Run the expected ranges and the forecast first, then
the scenarios, then each plan.

All of them read the metric's series: the newest periods inside the
metric's window, 48 months by default ([views](views.md)). A longer
history in the table is not sent. Where a metric's rows are finer
than its grain, the period the data ends inside is left out of all
three requests: the last period sent is the last complete one.

## Expected ranges

`metric_ranges()` tests each metric's monthly total against its own
history. For each of the latest six months the service gets the
months before it and returns the range that month was expected in:
a backtest. A metric needs seven complete months. Where the rows are
finer than monthly, a month the data ends inside is left out.
`backtested` in `range_points()` counts the months tested.

```glossql
SELECT metric_ranges() FROM subway;
```

```sql
SELECT metric, period, actual, p05, p50, p95, pit FROM range_points() WHERE newest;
```

An expected range is a statistical interval. For a count or another
value that cannot be negative, its lower bound can still lie below
zero.

`trains_run` was 73,479 in August 2025, in a range of 69,225 to
78,245, with `pit` 0.50. `pit` says where the actual fell in the
range: 0.5 is the middle. `range_test` is red where the newest month
has a `pit` below 0.01 or above 0.99. `next` then names the metric,
the value and the range. Cut at April 2020 the same metric was
21,236 against a range of 52,760 to 74,873, and the test was red.

A measured limitation (preview): the ranges are narrower than their
nominal level. In the evaluation's backtests the 90% range (`p05` to
`p95`) covered 63% of the actual values: 34 of 54 monthly points
from six datasets. Source: finding GV-18 of the evaluation
repository. Read a value outside its range as a reason to look, not
as proof of a defect.

A defect in the data and a real change look the same here. Fix a
defect in the load or the definition. State a real change as an
assumption with the key `range-<period>` in the metric's definition;
`next` gives the statement. The finding then waits for a person and
leaves `next`.

## Forecasts

`metric_forecast()` asks for the periods after the last complete one
with a value, at the metric's finest grain: 31 days, 13 weeks, 12 months or
4 quarters. A metric needs six periods of history. Metrics at minute,
hour or year grain are not forecast. An additive metric also gets
totals: to the end of the month at day grain, of the quarter at week
grain, of the quarter and the year at month grain, of the year at
quarter grain.

```glossql
SELECT metric_forecast() FROM subway;
```

```sql
SELECT metric, step, span, to_go, period, p10, p50, p90, actual, held_80, held_from
FROM forecast_points();
```

A row without `span` is one period: September 2025 at 71,802, between
68,274 and 74,583. A row with `span` is a total over that many
periods, to the end of `to_go`: 291,754 trains from September to the
end of the year. `held_80` says how often such a range held, and
`held_from` whose count it is: `service` (0.75 here, the service's
share on held-out data) until 30 forecast points of the metric or of
the dataset have their actuals.

`actual` fills in once the periods are loaded. September 2025 came in
at 71,992; `actuals` read `inside`. `forecast_coverage()` counts how
often the actuals fell inside the ranges, over every stored forecast.
A forecast run twice from the same last period counts once: one point
per metric, origin and step, from the newer run.
`metric_series(world := 'forecast')` serves the medians as a series.

## Plans

A plan is a budget, a target or a timetable for one metric. Its
numbers are a loaded table, described like any other table. Declare
the plan as a view of its own that names its metric, and define it
with SQL. Its period and value columns carry the names of the
metric's, or `period` and `value`:

```glossql
DECLARE ASPECT timetable WITH $${"title": "Timetable",
  "x-kind": "plan", "x-plan-of": "trains_run"}$$ AS VIEW;
GLOSS timetable ON subway AS $${
  "sql": "SELECT month, num_sched_trains AS value FROM timetable_months"
}$$;
SELECT metric_forecast() FROM subway;
SELECT metric_plan() FROM subway.timetable;
```

- `x-plan-of` names the metric. The plan takes the metric's
  additivity.
- `"x-covers": "year"` or `"quarter"` in the declaration says each
  row is booked against that period, such as a year's budget booked
  in January.
- Two editions of a budget are two plans.

```sql
SELECT period, value FROM metric_series(world := 'plan', plan := 'timetable')
WHERE dimension = '' ORDER BY period;
```

```sql
SELECT plan, label, value, actual, variance, low, expected, high, planned
FROM plan_points();
```

`plan_points()` has one row per plan and period, and one per year.
`planned` says where the row is:

| `planned` | Meaning |
|---|---|
| `complete` | the period is over and the actuals cover all of it; `variance` is actual minus plan |
| `not_covered` | the period has begun and the actuals served do not cover it: no `actual`, no `variance` |
| `inside`, `below`, `above` | the plan against the forecast's 80% range, `low` to `high` |
| `partial` | a year the plan's rows cover in part, begun |
| `open` | begun, and no forecast covers the rest |
| `ahead` | not begun, and no forecast for it |

The 2025 timetable held 911,197 trains. With 578,805 run by August
and the forecast for the rest, the year's range was 859,630 to
879,368: `above`. A year is compared where the plan's rows cover all
of it and the actuals do too. The actuals are the metric's series,
48 months here. With data through August 2025 it begins in September
2021: the timetable's years 2015 to 2021 read `not_covered`, and 2022
to 2024 read `complete`.

`metric_plan()` stores the comparison with the forecast it used. On a
view that is not a plan it is refused and stores nothing.
`plan_test` is red where a period lies outside the range. For a year
outside it, `next` names the gap; state it as an assumption with the
key `plan-<year>` in the plan's definition.

## Scenarios

A scenario changes a lever by a factor per period and asks the
service what the metric would do. A lever is a column of the metric's
view that someone sets, such as a price or a timetable. The view must
serve the column. Annotate it, declare the scenario, give the
factors, and run the estimate:

```glossql
GLOSS lever ON trains_run.scheduled AS $${"value": true,
  "basis": "the timetable, set by the operator for each month"}$$;

DECLARE ASPECT timetable_cut WITH $${"title": "Timetable cut by 5% from October 2025",
  "x-kind": "scenario", "type": "object", "required": ["levers"]}$$ AS FACT ON DATASET;
GLOSS timetable_cut ON subway AS $${"levers": [
  {"column": "trains_run.scheduled",
   "factor": {"2025-10": 0.95, "2025-11": 0.95, "2025-12": 0.95},
   "basis": "a proposal to schedule 5% fewer trains in the last quarter"}
]}$$;
SELECT metric_scenario() FROM subway;
```

A period is a month (`YYYY-MM`) or a day (`YYYY-MM-DD`); a period not
named keeps a factor of 1. The conditions:

- The metric has 26 periods of history.
- The scenario names a period after the metric's last complete
  period. Once those periods are loaded, the scenario returns a
  reason and no estimate, and `next` asks for later periods with the
  scenario's statement.
- A factor differs from 1.

The estimate covers the periods from the first after the last actual
to the last one named. Without the change, the lever follows its own
forecast (`planned_from = 'forecast'`), or keeps its last value where
it has fewer than six periods.

```sql
SELECT metric, period, low, value, high, baseline, effect, held_80, sign, confidence, reason
FROM scenario_points('timetable_cut');
```

```sql
SELECT lever, planned_from, history_shift, history_low, history_high
FROM scenario_levers('timetable_cut');
```

`scenario_points()` returns the metric under the scenario per period:
70,966 trains in October 2025, between 69,269 and 72,470, with the
service's `sign` (`-`), `confidence` and `basis`. `baseline` is the
same estimate with every lever as planned, and `effect` is `value`
minus `baseline`: 74,348 trains without the cut in October, so the
cut takes 3,381. September, which the scenario does not change, has
an effect of 0. Read the effect from these two columns. The
forecast's medians come from another model and differ in a month
with no change too (71,802 for September against 70,815 here).

`scenario_levers()` returns what each lever does alone:
`history_shift` is the mean change per period, here 2,939 fewer
trains run, between 3,329 and 2,488. Interactions between levers are
not estimated.

`held_80` comes from the newest forecast; run the forecast first.

## Without the service, and when a call fails

- No service named: `metric_ranges()`, `metric_forecast()` and
  `metric_scenario()` are refused, and the reason names
  `GLOSSDB_SERVICE_URL`. The query endpoint answers 503. `next` lists
  no preview row, and the rest of the server works. Plans read, and
  `metric_plan()` stores actual and variance without a range.
- Service not reachable, or it refuses the request: the call is
  refused with the service's error (503 on the query endpoint),
  nothing is stored, and `next` keeps the function listed.
- Too little history: the function runs and stores a reason per
  metric. Read `applicable` and `reason` in the feature's read. A
  result with no number in it is not green: `range_test`,
  `forecast_test` and `scenario_test` have no row in `TESTS()` then,
  and `view_tests()` shows the test as `not_applicable` with the
  reason. `next` lists nothing for it, since nobody can add history.
- A scenario that cannot be estimated for a reason its author can
  settle (no period ahead, every factor 1, a column that is no lever)
  shows as `not_run`, and `next` lists it with the statement to change.
