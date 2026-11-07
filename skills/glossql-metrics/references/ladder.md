# The series, the worlds and the bands walk — read when a metric's floor, window or axes are not what you expected

## The series

A metric is a view, and the series read serves its cells from the
view at read: nothing is built, nothing is stored. The view's
columns carry the words: the column with `role` timestamp is the
period, the column with `role` measure the value (the one named
`value` where several do), the columns with `role` dimension the
slices. The `behavior` on the value column says how the number
combines — a flow sums, a stock keeps the bucket's last level, a ratio
re-divides its summed halves, `numerator` and `denominator` naming
them. The time grains, the `ladder` aspect on the period column, say how
the periods are read: `floor`, the grain the series is served at, by default the
cadence `temporal()` measured on that column; `windows`, the window (rung) per
grain, how many whole buckets a read serves, measured back from the
data's edge.

```glossql
GLOSS ladder ON throughput.date AS $${"floor": "month", "windows": {"month": 120}}$$;
```

- `metric_series(grain := 'month')` serves every applicable metric
  at the asked grain, a metric coarser than it serving no rows;
  without a grain, each at its own floor. A window of `n` buckets is
  `n` whole buckets, the edge's bucket the last.
- A flow's empty period is a zero cell up to the data's edge — the
  last instant any served metric reaches — so a flow whose rows
  stopped early shows its zeros, not an older window. A stock's or a
  ratio's empty period is no cell.
- **The no-claim rule.** Where rows have to be combined and the value
  column has no `behavior`, the read refuses and names the missing
  annotation; it defaults nothing. `unclaimed := 'skip'` lists the
  rest, and the summary row says what the metric still needs.
- A dimension wider than 24 members serves its top 23 by weight and
  `other`; never read `other` as a business member. If that is too
  coarse, serve a narrower column from the metric's own SQL.
- The axes are the served columns that carry `role` dimension; a
  `dimension` annotation ranks them, `primary` first, `none` closes one.
  `metric_axes().unranked` names the ones no annotation ranks,
  `unadmitted` the served columns with no role, and `owed` the
  annotation each needs.

Where every metric is, in one read — from the catalog:

```sql
SELECT name, title, unit, meaning, formula
FROM metric_surfaces ORDER BY name
```

What the catalog says of each metric's columns, and what a series can
be served from:

```sql
SELECT metric, applicable, reason, behavior, cadence, floor, rung, dims, unadmitted, owed
FROM metric_axes() ORDER BY metric
```

And the cells — one row per metric, dimension, member and period at
the asked grain. `dimension = ''` is the metric's own total, anything
else a served dimension; a ratio row carries `num` / `den`, and
`behavior` is the verb that made the row. `world` says which set of
numbers a row is: `actual` unless asked. This is what an app frame
charts:

```sql
SELECT metric, period, value FROM metric_series(grain := 'month')
WHERE dimension = '' ORDER BY metric, period
```

After applying a batch of review decisions, run `temporal()` over the
period columns once; `judged_current` is true on the console's next
load. The
`review` and `slices` goals carry that order on the `next:` line.

## The bands walk

`metric_bands` asks, per metric and recent month: knowing only what
came before, what would this month have had to be for nobody to be
surprised? PIT says where the actual fell in that corridor — 0.5 is
on the trajectory, past 0.95 or under 0.05 is outside what the
metric's own history can explain. The service's result scores the
newest point of every metric walked, and the test `bands_w` carries it. Each
point's fit saw only the months before it.

- **The walk is the `bands` goal.** `SELECT metric_bands() FROM
  <dataset>` runs it; the `next:` line says when it is due and when
  it is current, and the console's re-measure runs it too.
- **The read is recall, you are the judge.** A business shift and a
  data defect breach identically.
- The walk sends complete months only, seven at least; a month the
  data's edge falls inside is left out where rows arrive finer than
  monthly.
- A red `metric_bands` result names its metric and month through
  `band_points()` — the stored walk as rows, no re-run. A defect is
  for the metric definition to fix; a shift is for the person to hear:
  record it as an assumption under the key `band-<period>` in the
  metric's definition, and the console asks. The walk is due again
  when a metric definition or the data changes.
- A declared fact (`x-kind: scalar`) `fact_values()` serves whole, its
  number where the view is one row with a value; a derived relation
  serves as its view alone.

## The forecast at an origin

`metric_forecast` asks the service, per metric, for the periods ahead
from the last period with a value — twelve months, thirteen weeks,
thirty-one days or four quarters by the metric's floor — and for a
flow the totals to the end of the month, the quarter or the year.
`SELECT metric_forecast() FROM <dataset>` runs it; after a load it is
due again, since the origin moved.

- `forecast_points()` is the latest forecast as rows; `actual` and
  `landed` fill as the periods arrive. `held_80` and `held_90` say how
  often such a band held, `held_from` whose count: this metric's
  history once 30 of its points arrived at that step, else the dataset's,
  else the service's held-out share. Hand a range out with them.
- `metric_series(world := 'forecast')` serves the newest run's medians
  as cells beside the actuals, at the metric's own floor; the default
  read is the actual world alone.
- `forecast_coverage()` counts, over every forecast stored, how often
  the actual fell inside the 80% and 90% bands per step: the rows
  `held_80` comes from once one reaches 30 points.
- No PIT: a forecast is written before the actual exists, and five
  quantiles say the band it fell in, not its exact place.

## The scenario world

A lever is a column of a metric's view that someone sets, annotated
on it: `GLOSS lever ON net_sales.unit_price AS $${"value": true,
"grounds": "the list price, set by sales"}$$`. A scenario is one FACT
aspect per scenario with `x-kind: scenario`, annotated with `levers`:
per lever the column as `metric.column`, a factor per period
(`"2027-01": 1.15`; `YYYY-MM` a month, `YYYY-MM-DD` a day) and the
basis. `scenarios()` judges every scenario: annotated, each lever an
annotated lever on a served metric's column, the factor a map.

- `SELECT metric_scenario() FROM <dataset>` runs the estimate for
  every scenario: each lever forecast on its own as the planned input
  (held at its last value where the forecast refuses), then the
  what-if route for every metric the levers reach. It needs 26
  periods of history and a lever that moves; a scenario that moves
  nothing is judged, not sent. The estimate is due again when the
  data or a scenario annotation moves.
- `metric_series(world := 'scenario', scenario := 'price_hike')`
  serves the estimate's medians ahead of the last actual beside the
  actual and the forecast worlds. No metric definition is replayed over
  the data.
- `scenario_points('price_hike')` serves the cells with the model's
  band (`low`, `high`), the history's own reading, how often such a
  band held (`held_80`, `held_from`) and the service's `sign`,
  `confidence` and `basis`. Hand an estimate out with its band and
  its share.
- Several levers are read as one change: the history adds what each
  does, and `scenario_levers('price_hike')` serves each lever's part
  per metric with `planned_from`, so the single levers and the pair
  read as one picture. A combination the history never held together
  states no sign, and an interaction between levers is not read.

## The plan world

A plan — a budget, a reforecast, a target — arrives as a loaded table,
and the glossary holds how to read it. A plan is one VIEW aspect per
plan, declared with `x-kind: plan` and `x-plan-of: <metric>`, the
metric it plans, and defined by SQL like a metric: `DECLARE ASPECT
revised_budget WITH $${"title": "Revised budget", "x-kind": "plan",
"x-plan-of": "expense"}$$ AS VIEW;` then `GLOSS
revised_budget ON fin AS $${"sql": "SELECT month AS date, revised AS
value FROM budget"}$$;`. The plan is read through the metric it
plans: its period and value are the columns named as that metric's,
or `period` and `value`; its behaviour is the metric's; nothing is
annotated on its own columns. `metric_axes()` lists it with its result,
`plan_of` naming the metric. A row covers its own period; where a
row's value is booked against the year — the adopted budget on the
January row — the declaration adds `x-covers: year` and the plan
reads at the year. One aspect per edition: the adopted budget and the
amended one both exist.

- `metric_series(world := 'plan', plan := 'revised_budget')` serves
  the plan's cells under the metric it plans, `metric` the metric and
  `world` `plan`, at the plan's own grain or any coarser grain asked.
  The actual world never carries them.
- A variance against the plan is a join of two worlds on `metric` and
  `period` at the plan's grain or coarser; a forecast against the plan
  is the same join with `world := 'forecast'`; two editions are a join
  of two plan reads.
- A year's budget beside monthly actuals reads at the year: the month
  cells are what the ledger booked that month. The engine spreads
  nothing; a phased budget is the planner's own table.
- `plan_points()` serves every plan against the actual and the
  forecast, one row per plan and period at the plan's own grain and at
  the year: the plan's number, the actual where the period has begun,
  the variance where it is complete, and the forecast's median with
  its 80% band where it covers the rest — at the year, the actual to
  date plus the year to go. The `stands` column says where the plan lies:
  `landed`, `inside`, `below` or `above` the band, `open` or `ahead`,
  and `partial` where the plan's rows cover part of the year — the
  year row then carries `covers` (`9 of 12 months`), its number and
  its actual over the covered months, and no band. A band at a coarser
  grain exists on a flow where the forecast asks a total to go, and on
  a stock as the band of the period's last month — a year-end
  headcount against December's forecast; a ratio's plan is loaded at
  the metric's own grain, one row for the month it is due, and
  compares to that month's band.
- `SELECT metric_plan() FROM <dataset>.<plan>` judges the plan: the
  same rows stored as a measurement on the plan with the forecast run
  they were judged against, `plan_w` reading the gap off them. The
  plan goal reads the judgement and never the data. Its next steps:
  the first plan to declare, a declared plan to define, the forecast
  to run while due, the plan to judge, then per plan year the band does
  not hold — a scenario on a lever that closes the gap, its estimate
  run, or the gap recorded as an assumption under `plan-<year>` in the
  plan's body for a person to decide; `next://<dataset>/plan` hands the
  statements filled. A plan's table is no edge of the actuals: a
  budget loaded through the year's end stretches no metric's series.
