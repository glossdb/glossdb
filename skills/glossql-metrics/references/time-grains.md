# Time grains and the preview features — read when a metric's grain, window or dimensions are not what you expected

## How a metric is served

A metric is a view. `metric_series()` reads it at query time; nothing
is built or stored. The annotations on the view's columns say how:

- `role`: `timestamp` is the period column, `measure` the value (the
  one named `value` where there are several), `dimension` a slice.
- `additivity` on the value column: additive sums; semi-additive
  keeps the period's last level; a ratio divides its summed
  `numerator` by its summed `denominator`.
- `time_grains` on the period column: `floor` is the finest grain
  served, by default the cadence `temporal()` measured on that column.
  `windows` is how many whole periods a read returns per grain,
  counted back from the newest data.

```glossql
GLOSS time_grains ON throughput.date AS $${"floor": "month", "windows": {"month": 120}}$$;
```

- `metric_series(grain := 'month')` serves every applicable metric at
  that grain; a metric whose floor is coarser serves no rows. Without
  a grain, each metric is served at its own floor. A window of `n` is
  `n` whole periods, ending with the newest.
- The newest data is the latest date any served metric reaches. An
  additive metric's empty period is a zero up to that date, so a
  metric whose rows stopped early shows zeros, not an older window. A
  semi-additive metric's or a ratio's empty period is no row.
- Where rows must be combined and the value column has no
  `additivity`, the read refuses and names the missing annotation. It
  defaults nothing. `unclaimed := 'skip'` serves the other metrics.
- A dimension with more than 24 members serves its top 23 by weight
  and `other`. `other` is never a business member. If that is too
  coarse, serve a narrower column from the metric's own SQL.
- The dimensions are the served columns with `role` dimension. A
  `dimension` annotation ranks them: `primary` first, `none` hides
  one. In `metric_summary()`, `unranked` lists the dimensions without
  a rank, `unadmitted` the served columns without a role, and
  `missing` the annotation each needs.

Every metric with its business description:

```sql
SELECT name, title, unit, meaning, formula
FROM metric_surfaces ORDER BY name
```

What each metric can be served from:

```sql
SELECT metric, applicable, reason, additivity, cadence, floor, rung, dims, unadmitted, missing
FROM metric_summary() ORDER BY metric
```

The numbers: one row per metric, dimension, member and period.
`dimension = ''` is the metric's total. A ratio row carries `num` and
`den`. `additivity` says how the row was combined. `world` says which
set of numbers the row belongs to: `actual` unless you ask for
another. A console page charts this:

```sql
SELECT metric, period, value FROM metric_series(grain := 'month')
WHERE dimension = '' ORDER BY metric, period
```

After applying a batch of review decisions, run `temporal()` over the
period columns once; `metric_summary().judged_current` is then true.
The `next:` line names this step.

`fact_values()` serves each single value (`x-kind: scalar`). A derived
relation (`x-kind: relation`) is read as its view.

## Expected ranges (preview)

`metric_bands` asks, per metric and recent month: given only the
months before, what range would this month fall in? `PIT` says where
the actual fell in that range: 0.5 is the middle; above 0.95 or below
0.05 is outside what the metric's history explains. The test
`bands_test` carries the score of each metric's newest month.

- `SELECT metric_bands() FROM <dataset>` runs it. It is a step of the
  `outlook` goal: the `next:` line says when it is due. It is due
  again when a metric definition or the data changes.
- It sends complete months only, at least seven. Where rows arrive
  finer than monthly, the month the newest data falls in is left out.
- `band_points()` serves the stored run as rows and names the metric
  and month of a red result. Nothing is run again.
- You judge the result. A business shift and a data defect look the
  same. Fix a defect in the metric definition. Tell a person about a
  shift: record it as an assumption with the key `band-<period>` in
  the metric definition, and the console asks.

## Forecasts (preview)

`metric_forecast` asks the model service, per metric, for the periods
after the last one with a value: twelve months, thirteen weeks,
thirty-one days or four quarters, by the metric's floor. For an
additive metric it also returns the totals to the end of the month,
the quarter and the year. `SELECT metric_forecast() FROM <dataset>`
runs it. It is due again after every load.

- `forecast_points()` is the newest forecast as rows. `actual` and
  `actuals` fill in as the periods arrive. `held_80` and `held_90` say
  how often such a range held. `held_from` says whose count that is:
  this metric's once 30 of its points have arrived at that step,
  otherwise the dataset's, otherwise the service's held-out share.
  Give these with every range you hand out.
- `metric_series(world := 'forecast')` serves the newest forecast's
  medians beside the actuals, at the metric's floor.
- `forecast_coverage()` counts, over every stored forecast, how often
  the actual fell inside the 80% and 90% ranges per step.
- A forecast has no PIT. It is written before the actual exists, and
  five quantiles give the range the actual fell in, not its exact
  place.

## Scenarios (preview)

A lever is a column of a metric's view that someone sets. Annotate it:

```glossql
GLOSS lever ON net_sales.unit_price AS $${"value": true, "grounds": "the list price, set by sales"}$$;
```

A scenario is one FACT aspect with `x-kind: scenario`, annotated with
`levers`: per lever the column as `metric.column`, a factor per period
(`"2027-01": 1.15`; `YYYY-MM` is a month, `YYYY-MM-DD` a day) and the
basis. `scenarios()` checks each scenario: it is annotated, each lever
is an annotated lever on a served metric's column, the factor is a
map.

- `SELECT metric_scenario() FROM <dataset>` estimates every scenario.
  Each lever is forecast on its own as the planned input, or held at
  its last value where the forecast refuses. Then the service
  estimates every metric the levers reach. It needs 26 periods of
  history and a lever that moves. A scenario that moves nothing is
  checked, not sent. The estimate is due again when the data or a
  scenario annotation changes.
- `metric_series(world := 'scenario', scenario := 'price_hike')`
  serves the estimate's medians after the last actual. No metric
  definition is run again over changed data.
- `scenario_points('price_hike')` serves the estimate with the model's
  range (`low`, `high`), how often such a range held (`held_80`,
  `held_from`), and the service's `sign`, `confidence` and `basis`.
  Give an estimate with its range and that share.
- Several levers are read as one change. `scenario_levers('price_hike')`
  serves each lever's part per metric, with `planned_from`. A
  combination the history never saw together states no sign, and
  interactions between levers are not estimated.

## Plans (preview)

A plan (a budget, a reforecast, a target) is a loaded table. Declare
one VIEW aspect per plan with `x-kind: plan` and `x-plan-of`, the
metric it plans, and define it with SQL like a metric:

```glossql
DECLARE ASPECT revised_budget WITH $${"title": "Revised budget", "x-kind": "plan", "x-plan-of": "expense"}$$ AS VIEW;
GLOSS revised_budget ON fin AS $${"sql": "SELECT month AS date, revised AS value FROM budget"}$$;
```

- The plan is read through its metric. Its period and value columns
  carry the same names as the metric's, or `period` and `value`. Its
  additivity is the metric's. Its own columns are not annotated.
- `metric_summary()` lists the plan; `plan_of` names its metric.
- A row covers its own period. Where a row holds the whole year (the
  adopted budget on the January row), add `x-covers: year` to the
  declaration and the plan is read at the year.
- One aspect per edition: the adopted budget and the amended one both
  exist.
- `metric_series(world := 'plan', plan := 'revised_budget')` serves
  the plan under its metric's name, at the plan's grain or a coarser
  one. The actual numbers never include it.
- A variance is a join of the plan and the actuals on `metric` and
  `period`, at the plan's grain or coarser. Forecast against plan is
  the same join with `world := 'forecast'`. Two editions are a join of
  two plan reads.
- A yearly budget beside monthly actuals is compared at the year.
  Nothing is spread over months; a phased budget is the planner's own
  table. A budget loaded to the year's end does not extend any
  metric's series.

`plan_points()` compares every plan with the actual and the forecast:
one row per plan and period, at the plan's grain and at the year. Each
row has the plan's number, the actual once the period has begun, the
variance once it is complete, and the forecast's median with its 80%
range for the rest. At the year that is the actual to date plus the
forecast to year end.

- `planned` says where the plan lies: `complete`; `inside`, `below` or
  `above` the range; `open` or `ahead`; `partial` where the plan's
  rows cover part of the year. A `partial` year row carries `covers`
  (`9 of 12 months`), its number and actual over those months, and no
  range.
- A range at a coarser grain exists for an additive metric where the
  forecast returns a total to go, and for a semi-additive metric as
  the range of the period's last month: a year-end headcount against
  December's forecast. A ratio's plan is loaded at the metric's grain,
  one row for the month it is due, and compared with that month's
  range.

`SELECT metric_plan() FROM <dataset>.<plan>` stores those rows as a
measurement on the plan, with the forecast they were compared to. The
test `plan_test` reads the gap from them. Declare a plan when a person
asks for one or a loaded table is a budget. The planned metric's steps
on the `next:` line then give the statements in order: define the
plan, run the forecast while it is due, run `metric_plan()`. For a
plan year outside the range: a scenario on a lever that closes the
gap and its estimate, or the gap recorded as an assumption with the
key `plan-<year>` in the plan's definition for a person to decide.
