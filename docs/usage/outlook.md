# Forecasts, expected ranges, plans and scenarios

**Status: preview.** These features exist for metrics only. Tables and
single values have none. They come in two kits, each a pull-in: a
server opened without them serves the rest unchanged, and `next` is
the same for a dataset with no stored result of theirs.

- **The plan kit** (`kits/plan`) compares a plan with its metric's
  actual. It needs no model service.
- **The outlook kit** (`kits/outlook`) asks a model service for
  expected ranges, forecasts and scenario estimates. The service is
  named once as `GLOSSDB_SERVICE_URL`
  ([configuration](../reference/configuration.md)). The binary carries
  no model.

Where a forecast is stored on a metric, the plan comparison holds the
plan's open periods against the forecast's range. Without one, they
stay open.

Each feature is a function you run when a person asks for it. The
kit builds the request from the lake, calls the service, stores the
answer, and serves it back as SQL. The service returns the verdicts:
the ranges, each metric's score and state, the coverage of a range,
the sign and the effect of a scenario, and a code for what it could
not answer. The kit stores them as they come.

| Feature | Kit | Run | Read | Test |
|---|---|---|---|---|
| Expected ranges | outlook | `SELECT metric_ranges() FROM <dataset>` | `range_points()` | `range_test` |
| Forecast | outlook | `SELECT metric_forecast() FROM <dataset>.<metric>` | `forecast_points()`, `metric_series(world := 'forecast')` | |
| Scenario | outlook | `SELECT metric_scenario() FROM <dataset>.<metric>` | `scenario_points('<name>')`, `scenario_levers('<name>')`, `metric_series(world := 'scenario', scenario := '<name>')` | |
| Plan | plan | `SELECT metric_plan() FROM <dataset>.<plan>` | `plan_points()`, `metric_series(world := 'plan', plan := '<name>')` | `plan_test` |

The columns of each read:
[reads](../reference/reads.md#the-outlook-and-plan-kits-preview).
`range_test` and `plan_test` are rows of `TESTS(<dataset>)` and
`TESTS(<dataset>.<plan>)`, and rows of `view_tests()`: the range test
on the dataset, with no view, the plan's test on the plan. The stored
result carries the `finding` and the `fix` of a red one, and of a
yellow `plan_test`.

The examples are from one run against a model service: New York
subway service per month. The metric `trains_run` is the trains that
ran, with the actuals loaded through August 2025. The timetable is
loaded through August 2026.

With the service on the same machine and 48 months of history
(measured): the expected ranges of three metrics took 0.7 to 1.4
seconds, a forecast of one metric 0.7 seconds, a scenario estimate 2
to 4 seconds (a forecast of each lever, then the estimate), a plan
comparison 1 second.

## When to run each one

The server runs none of them after a write, and `next` does not ask
for them before one is stored.

- `metric_ranges` once the metrics are served. It runs on the
  dataset: the service scores every metric in one request.
- `metric_forecast` once a metric is served, on that metric. A plan is
  held against its ranges.
- `metric_scenario` once a scenario is annotated and its levers hold,
  on each metric whose lever it sets.
- `metric_plan` once per plan.

Once a result is stored, `next` lists it as any stored result. A red
test on it (`range_test`, `plan_test`) is a `must` row with the
result's own finding and fix. A yellow `plan_test` is a `should` row
with its finding and fix. A result that is out of date is a
`should` row with the statement that computes it again. A result is
out of date by the rule every stored result follows: what it read
changed. What each one reads:

| Result | On | Reads |
|---|---|---|
| expected ranges | the dataset | every metric of the dataset: its data and definition, `role`, `additivity`, `dimension` and `time_grains` on its columns, its period column's temporal profile; the threshold of `range_test` |
| forecast | a metric | the same for that metric alone |
| scenario estimate | a metric | the same for that metric, the scenarios and its `lever` annotations |
| plan comparison | a plan | the plan, its metric, and the forecast stored on its metric |

So a metric defined or loaded beside the others leaves their
forecasts, and the plans that read them, current. It puts the
expected ranges out of date.

All of them read the metric's series: the newest periods inside the
metric's window, 48 months by default ([views](views.md)). A longer
history in the table is not sent. Where a metric's rows are finer
than its grain, the period the data ends inside is left out: the last
period sent is the last complete one.

## Expected ranges

`metric_ranges()` tests each metric's monthly total against its own
history. For each of the latest six months the service gets the
months before it and returns the range that month was expected in:
a backtest. The request carries the threshold of `range_test` (0.98
unless the test is declared with another).

```glossql
SELECT metric_ranges() FROM subway;
```

```sql
SELECT metric, period, actual, p05, p50, p95, pit, displacement, score, state
FROM range_points() WHERE newest;
```

`trains_run` was 73,479 in August 2025, in a range of 69,225 to
78,245, with `pit` 0.50: the middle of the range. `displacement` is
how far from the middle, 0 to 1. `score` and `state` are the
service's result for the newest month. The test is the worst
metric's state, so `range_test` is red where the service judged a
metric red. `next` then has a `must` row that names the metric, the
value and the range. A metric the service could not backtest has a
`code`, such as `origins_short`, and a `reason`.

An expected range is a statistical interval. For a count or another
value that cannot be negative, its lower bound can still lie below
zero.

A measured limitation (preview): the ranges are narrower than their
nominal level. In the evaluation's backtests the 90% range (`p05` to
`p95`) covered 63% of the actual values: 34 of 54 monthly points
from six datasets. Source: finding GV-18 of the evaluation
repository. Read a value outside its range as a reason to look, not
as proof of a defect.

A defect in the data and a real change look the same here. Fix a
defect in the load or the definition, then run the backtest again.
Where a person accepts a real change, they record a tolerance at or
above the score on the dataset, with their reason, as for the views'
checks; a person's tolerance outranks an agent's. The row in `next`
gives the statement:

```glossql
GLOSS metric_ranges ON subway AS $${"tolerance": 1.0,
  "basis": "the timetable changed in August, decided by operations"}$$;
```

The tolerance is part of what the backtest reads, so the stored
result is out of date after it, and `next` asks for it again.

## Forecasts

`metric_forecast()` asks for the periods after the last complete one,
at the metric's finest grain: 31 days, 13 weeks, 12 months or 4
quarters. A metric at minute, hour or year grain is not forecast. An
additive metric also gets totals: to the end of the month at day
grain, of the quarter at week grain, of the quarter and the year at
month grain, of the year at quarter grain. How much history a
forecast needs is the service's to say: too little comes back as the
code `history_short` with what is needed and what is given.

```glossql
SELECT metric_forecast() FROM subway.trains_run;
```

```sql
SELECT metric, step, span, to_go, period, p10, p50, p90, coverage_80, coverage_80_se
FROM forecast_points();
```

A row without `span` is one period: September 2025 at 71,802, between
68,274 and 74,583. A row with `span` is a total over that many
periods, to the end of `to_go`: 291,754 trains from September to the
end of the year. `coverage_80` is the service's measured share of
actual values inside such an 80% range on held-out data, at that
grain and step, with its standard error. A run that fails is stored
as failed: `forecast_points()` shows the metric with its `error` and
no point, not the run before. `metric_series(world := 'forecast')`
serves the medians as a series.

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
SELECT plan, label, value, actual, variance, low, expected, high, planned, coverage_80
FROM plan_points();
```

`plan_points()` has one row per plan and period, and one per year.
`planned` says where the row is:

| `planned` | Meaning |
|---|---|
| `complete` | the period is over and the actuals cover all of it; `variance` is actual minus plan |
| `not_covered` | the period has begun and the actuals served do not cover it: no `actual`, no `variance` |
| `inside`, `below`, `above` | the plan against the stored forecast's 80% range, `low` to `high` |
| `partial` | a year the plan's rows cover in part, begun |
| `open` | begun, and no stored forecast covers the rest |
| `ahead` | not begun, and no stored forecast for it |

The 2025 timetable held 911,197 trains. With 578,805 run by August
and the forecast for the rest, the year's range was 859,630 to
879,368: `above`. A year is compared where the plan's rows cover all
of it and the actuals do too. The actuals are the metric's series,
48 months here. With data through August 2025 it begins in September
2021: the timetable's years 2015 to 2021 read `not_covered`, and 2022
to 2024 read `complete`.

`metric_plan()` stores the comparison, with the origin of the
forecast it used where one is stored. On a view that is not a plan it
is refused. `plan_test` is red where a period lies outside the range.
For a year outside it, `next` has a `must` row that names the gap;
state it as an assumption with the key `plan-<year>` in the plan's
definition.

A failed forecast is a result too. Where the newest forecast stored
on the metric failed (the service did not answer, or it answered a
code such as `history_short` and no point) and a period of the plan
is `open` or `ahead`, the plan has no range to hold against.
`plan_test` is then yellow, not green. The comparison carries the
forecast's `forecast_code` and `forecast_error`, and its fix runs the
forecast and the comparison again. Where no forecast was stored, the
periods stay `open` or `ahead` and the test is green.

## Scenarios

A scenario changes a lever by a factor per period and asks the
service what the metric would do. A lever is a column of the metric's
view that someone sets, such as a price or a timetable. The view must
serve the column. Annotate it, declare the scenario, give the
factors, and run the estimate on the metric:

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
SELECT metric_scenario() FROM subway.trains_run;
```

A period is a month (`YYYY-MM`) or a day (`YYYY-MM-DD`); a period not
named keeps a factor of 1. The scenario names a period after the
metric's last complete period. Once those periods are loaded, the
scenario returns a reason and no estimate: name later periods in the
scenario. `scenarios()` judges every scenario of the dataset: each
lever annotated, on a served metric's column, its factor a map. Where
one is not, `fix` annotates the scenario again with the body that was
judged.

The estimate covers the periods from the first after the last actual
to the last one named. Without the change, the lever follows its own
forecast (`planned_from = 'forecast'`), or keeps its last value where
the service cannot forecast it. How much history the estimate needs,
and whether the scenario changes an input at all, are the service's
to say: it answers the codes `history_short` and `nothing_changed`.

```sql
SELECT metric, period, low, value, high, baseline, effect, sign, basis, code, reason
FROM scenario_points('timetable_cut');
```

```sql
SELECT lever, planned_from, history_shift, history_low, history_high
FROM scenario_levers('timetable_cut');
```

`scenario_points()` returns the metric under the scenario per period:
`value` with `low` and `high`, `baseline` the same estimate with every
lever as planned, and `effect` the service's difference of the two.
`sign` is `+`, `-`, `0` (no effect visible) or `?` (no sign can be
stated), with the service's `basis`. No interval of a scenario has a
stated coverage.

`scenario_levers()` returns what each lever does alone:
`history_shift` is the mean change per period by the metric's own
history, with its 90% interval. Interactions between levers are not
estimated.

## Without the service, and when a call fails

- No service named: `metric_ranges()`, `metric_forecast()` and
  `metric_scenario()` are refused, and the reason names
  `GLOSSDB_SERVICE_URL`. The query endpoint answers 503. The rest of
  the server works, and the plan kit compares plans with the actual.
- Service not reachable, or it refuses the request: the call fails
  with the service's error (503 on the query endpoint). The failure
  is stored as the newest result, and the reads show it.
- What the service could not answer for one metric comes back with a
  `code` and a `reason` in the feature's read, and the other metrics
  are answered. A result with no number in it is not green:
  `range_test` has no row in `TESTS()` or `view_tests()` then.
