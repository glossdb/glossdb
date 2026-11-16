# Preview features: expected ranges, forecasts, plans, scenarios

These features are in preview. Label what you hand out from them as
preview. They apply to metrics only. Two kits serve them, and a server
may load neither:

- the plan kit compares a plan with its metric's actual, with no
  model service;
- the outlook kit asks a model service configured on the server for
  expected ranges, forecasts and scenario estimates.

Each is a function you run; the result is stored and read back as
rows. The service returns the verdicts: ranges, scores and states,
coverage, sign and effect, and a `code` for what it could not answer.
Read them as they are stored. The examples ran on a dataset of subway
service: the metric `trains_run` per month, actuals loaded through
August 2025, and a timetable loaded a year further.

## Functions you may run

Run them when the person asks for a range, a forecast, a plan
comparison or a scenario. They are not steps of the work on a
dataset: the server runs none of them, and `next` asks for none of
them before one is stored.

| Function | Run on | Once |
|---|---|---|
| `metric_ranges()` | the dataset | the metrics are served |
| `metric_forecast()` | a metric | it is served |
| `metric_scenario()` | a metric | a scenario sets one of its levers |
| `metric_plan()` | a plan | it is defined; with the forecast of its metric stored, it holds the open periods against its range |

With the service on the same machine, a forecast took 0.7 seconds, the
expected ranges up to 1.4, a scenario estimate 2 to 4 (measured).

Once a result is stored, `next` lists it as any stored result:

- `range_test` or `plan_test` red: a `must` row with the result's own
  finding and fix.
- `plan_test` yellow: the newest forecast of the plan's metric failed,
  and a period waits for a range. A `should` row: its finding names the
  forecast's `forecast_code`, its fix runs the forecast and the
  comparison again.
- The result out of date (what it read changed): a `should` row with
  the statement that computes it again. The expected ranges read
  every metric of the dataset; a forecast or a scenario estimate its
  own metric; a plan comparison the plan, its metric and the forecast
  stored on it. A new metric leaves the other metrics' forecasts and
  plan comparisons current.

Each function reads the metric's series inside its window, 48 months
by default (`time-grains.md`), up to the last complete period: where
the rows are finer than the metric's grain, the period the data ends
inside is left out. Where the service cannot answer for a metric, the
function still stores the answer: read `applicable`, `code` and
`reason` in the feature's read. Without a model service the functions
are refused with a reason that names `GLOSSDB_SERVICE_URL`, the
server's setting. A call that fails is stored as the newest result,
with its `error`.

`range_test` is a row of `view_tests()` on the dataset, with no view;
`plan_test` on the plan.

## Expected ranges

For each of a metric's latest six months: given the months before,
what range would this month fall in? That is a backtest. The service
scores every metric in one request against the threshold of
`range_test`. The ranges are monthly: a metric served by quarter or
year has none, and its `reason` says so.

```glossql
SELECT metric_ranges() FROM subway;
```

```sql
SELECT metric, period, actual, p05, p50, p95, pit, displacement, score, state, code, reason
FROM range_points() WHERE newest
```

A range is a statistical interval, so for a count or another value
that cannot be negative its lower bound can still lie below zero.
`pit` says where the actual fell in the range: 0.5 is the middle.
August 2025 was 73,479 in a range of 69,225 to 78,245, `pit` 0.50.
`state` is the service's for the metric; `range_test` takes the worst
metric's. `next` then has a `must` row that names the value and the
range. A change in the business and a defect in the data look the
same here. Fix a defect in the load or the definition, and run the
backtest again. A real change is a person's to accept: they record a
tolerance at or above the score on the dataset, with their reason, as
the statement in `next` shows. Do not record it for them.

## Forecasts

The periods after the last complete one: 31 days, 13 weeks, 12
months or 4 quarters, by the metric's finest grain. Minutes, hours
and years are not forecast. The service says when the history is too
short (`code` `history_short`).

```glossql
SELECT metric_forecast() FROM subway.trains_run;
```

```sql
SELECT metric, step, span, to_go, period, p10, p50, p90, coverage_80, coverage_80_se, code, error
FROM forecast_points()
```

A row without `span` is one period. A row with `span` is a total
over that many periods, to the end of `to_go`: an additive monthly
metric gets the total to the end of the quarter and of the year.
September 2025 was forecast at 71,802, between 68,274 and 74,583.
`coverage_80` is the service's measured share of actuals inside such
a range on held-out data, with its standard error. Hand a range out
with it. `metric_series(world := 'forecast')` serves the medians.

## Plans

A plan (a budget, a target, a timetable) is a loaded table. Load and
describe it like any table. Declare one view per plan, and per
edition of it, with `x-kind: plan` and `x-plan-of`, the metric it
plans. Then run the comparison:

```glossql
DECLARE ASPECT timetable WITH $${"title": "Timetable", "x-kind": "plan", "x-plan-of": "trains_run"}$$ AS VIEW;
GLOSS timetable ON subway AS $${"sql": "SELECT month, num_sched_trains AS value FROM timetable_months"}$$;
SELECT metric_plan() FROM subway.timetable;
```

The plan's period and value columns carry the names of the metric's,
or `period` and `value`. Its additivity is the metric's. A row covers
its own period; where one row holds the whole year, add `"x-covers":
"year"` to the declaration. `next` asks for `meaning` on the plan,
and for the annotations on the table it reads.

```sql
SELECT plan, grain, label, value, actual, variance, low, expected, high, planned, coverage_80
FROM plan_points()
```

One row per plan and period, and one per year. `planned` is
`complete` (the period is over and the actuals cover all of it;
`variance` is actual minus plan), `not_covered` (begun, and the
metric's series does not cover it: no `actual`, no `variance`),
`inside`, `below` or `above` the stored forecast's 80% range,
`partial` (a year the rows cover in part), `open` or `ahead` (no
stored forecast covers it). The series is the metric's window, so a
year before it, or one it enters part-way, reads `not_covered`: do
not report a variance for it. `metric_plan()` on a view that is not a
plan is refused. The 2025 timetable was 911,197 against a range of
859,630 to 879,368 for the year: `above`. The test `plan_test` is red
where a period lies outside the range, and yellow where the newest
forecast of the metric failed and a period waits for a range. For a year outside it, `next`
gives the statement: add an assumption with the key `plan-<year>` to
the plan's definition.

`metric_series(world := 'plan', plan := 'timetable')` serves the plan
under its metric's name, at the plan's grain or coarser.

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
SELECT metric_scenario() FROM subway.trains_run;
```

The scenario must name a period after the metric's last complete
period. After a load that covers its periods it returns a reason and
no estimate: give it later periods. `scenarios()` checks each
scenario before you run it; `fix` annotates it again with the body
that was checked. The service says when the history is too short
(`history_short`) or the scenario changes no input (`nothing_changed`).

```sql
SELECT metric, period, low, value, high, baseline, effect, sign, basis, applicable, code, reason
FROM scenario_points('timetable_cut')
```

```sql
SELECT lever, planned_from, history_shift, history_low, history_high
FROM scenario_levers('timetable_cut')
```

`scenario_points()` is the metric under the scenario, from the first
period after the last complete one to the last period named.
`baseline` is the same estimate with every lever as planned and
`effect` is the service's difference of the two. Report the effect
from these columns, not from the difference to the forecast: the
forecast comes from another model. `sign` is `+`, `-`, `0` (no effect
visible) or `?` (none can be stated; read `basis`). No range of a
scenario has a stated coverage: hand an estimate out as a direction
with its range, not as a number that holds. `scenario_levers()` is
what each lever does alone by the history: `history_shift` is the
mean change per period. `planned_from` says what the lever does
without the change: its own `forecast`, or its last value held. No
definition is run again over changed data, and interactions between
levers are not estimated.
`metric_series(world := 'scenario', scenario := 'timetable_cut')`
serves the medians.
