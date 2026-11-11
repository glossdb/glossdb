# Preview features: expected ranges, forecasts, plans, scenarios

These features are in preview. Label what you hand out from them as
preview. They apply to metrics only. Expected ranges, forecasts and
scenarios are computed by a model service configured on the server.
Each is a function you run on the dataset; the result is stored and
read back as rows. The examples ran on a dataset of subway service:
the metric `trains_run` per month, actuals loaded through August
2025, and a timetable loaded a year further.

## What `next` lists, and the order

With a model service, `next` lists each function that is due, with
its statement:

| Row of `next` | Listed |
|---|---|
| `metric_ranges (preview)` | once a metric is served |
| `metric_forecast (preview)` | once a plan has a definition or a scenario can be estimated |
| `metric_scenario (preview)` | once a scenario is annotated and its levers hold |
| `plan_test (preview)` | once per plan, and after each new forecast or a change to the plan |
| `scenario_test (preview)` | a scenario you can fix: no period ahead, every factor 1, a column that is no lever |

The server does not run them for you. `next` lists a function again
when what it reads changed: a load of a table the metric scans, a
change to the metric's SQL, columns, grain or additivity, and for a
scenario its levers and factors. Another view, a new plan, an
assumption or an annotation the series does not read leaves the
stored results as they are. Run them in this order: expected ranges,
forecast, scenario, then each plan. A call took 2 to 6 seconds on one
metric (measured).

Each function reads the metric's series inside its window, 48 months
by default (`time-grains.md`), up to the last complete period: where
the rows are finer than the metric's grain, the period the data ends
inside is left out. Where a metric has too little history, the
function still runs and stores a reason: read `applicable` and
`reason` in the feature's read. Its test is then not green:
`view_tests()` shows it as `not_applicable`, and `next` lists nothing
you could do. Without a model service the functions are refused with
a reason that names `GLOSSDB_SERVICE_URL`, the server's setting, and
`next` lists no preview row.

The four tests are rows of `view_tests()` under the metric; a plan's
test shows under the metric it plans.

## Expected ranges

For each of a metric's latest six months: given the months before,
what range would this month fall in? That is a backtest. A metric
needs seven complete months; `backtested` counts the months tested.
The ranges are monthly: a metric served by quarter or year has none,
and its `reason` says so.

```glossql
SELECT metric_ranges() FROM subway;
```

```sql
SELECT metric, period, actual, p05, p50, p95, pit, applicable, reason
FROM range_points() WHERE newest
```

A range is a statistical interval, so for a count or another value
that cannot be negative its lower bound can still lie below zero.
`pit` says where the actual fell in the range: 0.5 is the middle.
August 2025 was 73,479 in a range of 69,225 to 78,245, `pit` 0.50.
The test `range_test` is red where the newest month's `pit` is below
0.01 or above 0.99; `range_result()` is the run in one row. `next`
then names the value and the range. A change in the business and a
defect in the data look the same here. Fix a defect in the load or
the definition. Tell a person about a real change: add an assumption
with the key `range-<period>` to the metric's definition, as the
statement in `next` shows. The row then waits for the person.

## Forecasts

The periods after the last complete one with a value: 31 days, 13
weeks, 12 months or 4 quarters, by the metric's finest grain. A metric needs
six periods. Minutes, hours and years are not forecast.

```glossql
SELECT metric_forecast() FROM subway;
```

```sql
SELECT metric, step, span, to_go, period, p10, p50, p90, actual, actuals, held_80, held_from
FROM forecast_points()
```

A row without `span` is one period. A row with `span` is a total
over that many periods, to the end of `to_go`: an additive monthly
metric gets the total to the end of the quarter and of the year.
September 2025 was forecast at 71,802, between 68,274 and 74,583.
`held_80` says how often such a range held, and `held_from` whose
count that is: the service's share on held-out data (0.75 here),
until 30 forecast points of the metric or the dataset have their
actuals. Hand a range out with it. After the next load `actual`
fills in and `actuals` says `inside`, `low`, `high`, `below` or
`above`. `metric_series(world := 'forecast')` serves the medians;
`forecast_coverage()` counts how often actuals fell inside, one point
per metric, origin and step: a forecast run twice from the same last
period counts once.

## Plans

A plan (a budget, a target, a timetable) is a loaded table. Load and
describe it like any table. Declare one view per plan, and per
edition of it, with `x-kind: plan` and `x-plan-of`, the metric it
plans. Then run the forecast and the comparison:

```glossql
DECLARE ASPECT timetable WITH $${"title": "Timetable", "x-kind": "plan", "x-plan-of": "trains_run"}$$ AS VIEW;
GLOSS timetable ON subway AS $${"sql": "SELECT month, num_sched_trains AS value FROM timetable_months"}$$;
SELECT metric_forecast() FROM subway;
SELECT metric_plan() FROM subway.timetable;
```

The plan's period and value columns carry the names of the metric's,
or `period` and `value`. Its additivity is the metric's. A row covers
its own period; where one row holds the whole year, add `"x-covers":
"year"` to the declaration. `next` asks for `meaning` on the plan,
and for the annotations on the table it reads.

```sql
SELECT plan, grain, label, value, actual, variance, low, expected, high, planned, held_80
FROM plan_points()
```

One row per plan and period, and one per year. `planned` is
`complete` (the period is over and the actuals cover all of it;
`variance` is actual minus plan), `not_covered` (begun, and the
metric's series does not cover it: no `actual`, no `variance`),
`inside`, `below` or `above` the forecast's 80% range, `partial` (a
year the rows cover in part), `open` or `ahead` (no forecast covers
it). The series is the metric's window, so a year before it, or one
it enters part-way, reads `not_covered`: do not report a variance for
it. `metric_plan()` on a view that is not a plan is refused. The 2025 timetable was 911,197 against a range of 859,630 to
879,368 for the year: `above`. The test `plan_test` is red where a
period lies outside the range. For a year outside it, `next` gives
the statement: add an assumption with the key `plan-<year>` to the
plan's definition.

`metric_series(world := 'plan', plan := 'timetable')` serves the plan
under its metric's name, at the plan's grain or coarser. The plan
reads work without a model service.

## Scenarios

A lever is a column of a metric's view that someone sets, such as a
price or a timetable. The view must serve the column; `next` asks
for a `role` on the view's column, with the statement the view's
summary row names in `missing`, and for the annotations on the
column of the table it reads. A scenario changes levers
by a factor per period (`YYYY-MM` or `YYYY-MM-DD`; a period not named
keeps 1) and asks what the metric would do.

```glossql
GLOSS lever ON trains_run.scheduled AS $${"value": true, "basis": "the timetable, set by the operator for each month"}$$;
DECLARE ASPECT timetable_cut WITH $${"title": "Timetable cut by 5% from October 2025", "x-kind": "scenario", "type": "object",
  "required": ["levers"], "properties": {"levers": {"type": "array"}}}$$ AS FACT ON DATASET;
GLOSS timetable_cut ON subway AS $${"levers": [{"column": "trains_run.scheduled", "factor": {"2025-10": 0.95, "2025-11": 0.95, "2025-12": 0.95}, "basis": "a proposal to schedule 5% fewer trains in the last quarter"}]}$$;
SELECT metric_forecast() FROM subway;
SELECT metric_scenario() FROM subway;
```

The metric needs 26 periods of history. The scenario must name a
period after the metric's last complete period and a factor other
than 1. After a load that covers its periods it returns a reason and
no estimate, and `next` lists `scenario_test (preview)` with the
scenario's statement: give it later periods. `scenarios()` checks
each scenario before you run it.

```sql
SELECT metric, period, low, value, high, baseline, effect, held_80, held_from, sign, confidence, applicable, reason
FROM scenario_points('timetable_cut')
```

```sql
SELECT lever, planned_from, history_shift, history_low, history_high
FROM scenario_levers('timetable_cut')
```

`scenario_points()` is the metric under the scenario, from the first
period after the last complete one to the last period named: 70,966
in October 2025, between 69,269 and 72,470, `sign` `-`. `baseline`
is the same estimate with every lever as planned (74,348) and
`effect` is `value` minus `baseline` (3,381 fewer trains). Report
the effect from these columns, not from the difference to the
forecast: the forecast comes from another model.
`scenario_levers()` is what each lever does alone: `history_shift`
is the mean change per period, here 2,939 fewer trains.
`planned_from` says what the lever does
without the change: its own `forecast`, or its last value held.
`held_80` comes from the newest forecast, so run the forecast first.
No definition is run again over changed data, and interactions
between levers are not estimated. Hand an estimate out with its
range and `held_80`.
`metric_series(world := 'scenario', scenario := 'timetable_cut')`
serves the medians.
