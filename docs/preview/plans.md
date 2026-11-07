# Plans

Preview: comparing a plan with its forecast needs a model service,
named by `GLOSSDB_SERVICE_URL`
([configuration](../operations/configuration.md)), and may change.

A plan is a set of numbers someone decided for a metric: a budget, a
reforecast, a target. Its numbers arrive as a loaded table, thousands
of rows and an edition or two. The catalog holds what they mean: which
table, which column, which edition counts as the plan, and which metric
it belongs to. `metric_series(world := 'plan', plan := '<name>')`
returns the plan's cells beside the actual, forecast and scenario
worlds, under the metric it plans.

## Declaring a plan

A plan is a view aspect (`AS VIEW`) of its own, one per
plan, the way a metric is one per concept. Its declaration carries
`x-kind: plan` and `x-plan-of`, the metric it plans. Its annotation is
a metric definition like any other: SQL over the loaded table,
validated by the standard schema for metric definitions.

```glossql
DECLARE ASPECT revised_budget WITH $${
  "title": "Revised budget",
  "description": "The adopted budget with the council's amendments, as booked",
  "x-kind": "plan", "x-plan-of": "expense", "x-covers": "year", "x-unit": "USD"
}$$ AS VIEW;

GLOSS revised_budget ON brla AS $${
  "sql": "SELECT fiscalmonth AS date, revisedbudget AS value, fund, segment2 FROM expense_budget"
}$$;
```

The link is checked when the plan is read. `x-plan-of` must name a
declared view aspect of the dataset that is not itself a plan. The plan
must return the columns named as that metric's period and value, or
`period` and `value`. `metric_axes()` lists the plan with the result of
that check and how to fix it, with `plan_of` naming the metric.

**Coverage.** A row covers its own period: a monthly schedule plans
each month it names, and the plan covers the months it has rows for.
Where a row's value is booked against a coarser period, the declaration
says so: `x-covers` names the grain, `year` or `quarter`. Baton Rouge
books the adopted budget on the January row and each amendment on the
row of its month, so its budget carries `"x-covers": "year"` and is
read at the year; a month's cell is what was booked that month. A word
that is not a grain is refused at `DECLARE`.

**Editions.** Each edition of a plan is an aspect of its own. The
adopted budget and the amended budget both exist, each with its own
definition and assumptions, its own value, and its own test if wanted.
A new annotation corrects one edition's SQL; a person's annotation
replaces an agent's.

## Reading a plan

The plan's definition is a view under the plan's name, like a metric's.
The plan is read through the metric it plans:

- its period and value are the columns named as that metric's;
- its additivity is the metric's;
- its finest grain is the grain its rows are booked against, where the
  declaration says so, else its rows' cadence.

Nothing is annotated on a plan's own columns.
`metric_series(world := 'plan', plan := 'revised_budget')` returns the
cells with `metric` set to the metric the plan names and `world` set to
`plan`, at the plan's own grain or any coarser grain asked. A flow
sums; a stock keeps the last level. A finer grain returns no rows. The
actual world never carries a plan's cells, and expected ranges and
forecasts do not read it.

**Variance.** Against the plan, variance is a join of two worlds on
metric and period: the actual at `grain := 'year'` against the plan at
the same grain, `a.value - p.value`. Forecast against plan is the same
join with `world := 'forecast'` on one side. Original against revised
is a join of two plan reads. `world := 'plan'` without a name, and a
name that is not a plan aspect, are refused with the correct spelling.

**`plan_points()`** returns the comparison without the join, for every
plan at once. There is one row per plan and period, at the plan's own
grain and at the year, with:

- the plan's number;
- the actual, where the period has begun;
- the variance, where the period is complete;
- where the forecast covers the rest, its median with the 80% range:
  the step's range at the metric's own grain, and at the year the
  actual to date plus the year to go.

The row's `planned` column says where the plan is: `complete`, `inside`,
`below` or `above` the range, or `open` or `ahead` where no range
covers it ([views and table functions](../reference/reads.md)).

**Partial years.** The year row of a plan finer than the year says how
much of the year its rows cover, in `covers`: `9 of 12 months` where a
schedule runs to September, NULL where the rows cover the whole year.
Where they cover part of it, the plan's number and the actual are over
the covered months, the row is `complete` with its variance once those
months are complete and `partial` while they are not, and no range is
read: the forecast totals a year to go, never part of one. A plan
booked against the year (`x-covers: year`) is read at the year alone.

```sql
SELECT plan, label, value, actual, expected, low, high, planned
FROM plan_points() WHERE grain = 'year' ORDER BY plan, period
```

## Judging a plan

`metric_plan` judges a plan: `SELECT metric_plan() FROM
brla.revised_budget` stores the rows `plan_points()` returns for it as
a measurement on the plan, with the forecast run it was judged against.
The test `plan_w` reads the gap from that measurement: red where a
period with a range lies below or above the forecast's range, scored as
the share of such periods. The measurement is stale once the data or
the catalog rows it read change; a newer forecast asks for it again.

## The planning goal

The `next` read carries the plan as its own goal, `plan`, beside the
seven others ([views and table functions](../reference/reads.md),
`next`). Every step reads the catalog, never the data. The goal's steps
are the plan's preconditions, in order:

1. an applicable metric, else the goal is blocked;
2. the first plan to declare: its statement filled with the dataset,
   the names left to the author;
3. a declared plan to define, or to stop;
4. a plan the read refuses, to record again;
5. the forecast to run, if never run or stale;
6. the plan to judge, if never judged or judged against an older
   forecast.

Then every plan year whose range does not contain the plan is a gap.

- For a gap with nothing recorded on it, the action is a scenario on a
  lever (the lever annotated and the scenario declared with its
  factors, see [scenarios](scenarios.md)), or the gap recorded at once.
- With a scenario in place, the action is the estimate
  (`metric_scenario`), if never run or stale; then the comparison
  (`plan_points()` for the plan's row beside `scenario_points()` for
  the estimate and the service's view on the lever); then the decision.

Either way the next statement is the same: the decision as an
assumption under the key `plan-<year>` in the plan's own definition, at
confidence 0.7. The console asks a person. While the question is open
the goal is blocked; a review decision under that key closes it. With
no gap, the goal is done.

The goal judges the year. A budget booked by the month (the adoption
in January, an amendment in May) means nothing month by month and
something at the year, and the year to go is the total the forecast
asks for a month or quarter metric. A plan on a week or day metric has
no year to go: its year rows stay open, and the goal has no gap to
judge. A plan whose rows cover part of a year is `partial` at the year,
and the goal has no gap there either: its own months are held to their
ranges.

## Grain

A budget often comes at a coarser grain than the actual: a year's
number beside monthly spend. The plan's definition returns the date
column as it is, and the read buckets it as it buckets any flow. Where
a budget is booked in the month it was authorized (the adoption in
January, an amendment in May), the plan's month cells are what the
ledger booked that month, and the year is where the plan means
something. The declaration says so with `x-covers: year`, and the read
returns the year. A phased budget, a twelfth a month or a seasonal
curve, is a planner's own table, read at month grain. The engine
spreads nothing.

## Additivity and grain

A metric's additivity is how its number combines over time:

- a **flow** adds up: spend, revenue;
- a **stock** is a level at a moment: headcount, inventory. At a
  coarser grain the read keeps the last level;
- a **ratio** is a quotient: margin, win rate. At a coarser grain the
  read divides the summed halves again.

The forecast runs at the metric's own grain and gives a range for every
period ahead, whatever the additivity. It asks for a total to go, the
quarter or the year, only on a flow: a total of a stock or a ratio is
not a number ([forecasts](forecasts.md)). That decides what a plan is
compared with.

| Metric's grain | Additivity | Plan at the metric's grain | Plan at a coarser grain, or the year row |
|---|---|---|---|
| day | flow | a range per day, 31 ahead | the month to go only |
| day | stock | a range per day | the period's last day's range, within 31 days |
| day | ratio | a range per day | no range |
| week | flow | a range per week, 13 ahead | the quarter to go only |
| week | stock | a range per week | the period's last week's range, within 13 weeks |
| week | ratio | a range per week | no range |
| month | flow | a range per month, 12 ahead | the quarter and the year to go |
| month | stock | a range per month | the period's last month's range, within 12 months |
| month | ratio | a range per month | no range |
| quarter | flow | a range per quarter, 4 ahead | the year to go |
| quarter | stock | a range per quarter | the year's last quarter's range, within 4 quarters |
| quarter | ratio | a range per quarter | no range |
| year, hour, minute | any | no forecast | no range |

- A plan at the metric's own grain is compared with the range for that
  period, for every additivity.
- A plan at a coarser grain is compared, on a flow, with the actual to
  date plus the total to go. On a stock it is compared with the range
  for the last period of the metric's own grain inside it: a year-end
  headcount against December's forecast, with nothing added, where the
  horizon reaches it.
- A ratio at a coarser grain has no range: a year's margin is neither a
  sum nor a last level.
- A plan at a coarser grain is compared only where its rows cover the
  whole period. Where they cover part of it, the row carries `covers`
  and no range.
- Where the table says no range, `plan_points()` still returns the row
  with the actual and the variance, and `planned` says `open` or
  `ahead`.

The planning goal reads the year rows. So it finds a gap on a flow at
month or quarter grain, and on a stock whose year end the forecast
reaches. A margin target is loaded as one row for the month it is due,
and the read compares it with that month's range.

The read compares totals. A budget split by department is a plan per
department, each its own aspect with a filter in its definition.

## Limits

- One plan aspect returns one metric's numbers. A budget file of many
  lines is read by one plan aspect per line and edition, each
  definition filtering on its line.
- The plan's additivity is its metric's: a budget for a stock keeps its
  last level at a coarser grain, like the stock.
- A metric whose definition is stopped leaves its plans in place. The
  stop is in the metric's own `metric_axes()` row.
- A plan's table does not extend the actuals. A flow's empty periods
  are zeros up to the data's edge, the latest period the metrics'
  definitions return. A budget loaded through the year's end extends no
  metric, and the forecast's origin stays the last period with an
  actual. The plan's own cells reach the end of its own range.
- The plan's cells are read from its view at query time and change when
  the plan's table or its definition does. The judgment, `metric_plan`,
  is what the catalog stores.
