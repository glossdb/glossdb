# The plan world

A plan is a set of numbers someone decided for a metric: a budget, a
reforecast, a target. Its numbers arrive as a landed table, thousands
of rows and an edition or two, and the glossary holds what they mean:
which table, which column, which edition counts as the plan, and which
metric it belongs to. `metric_series(world := 'plan', plan :=
'<name>')` serves the plan's cells beside the actual, the forecast and
the scenario worlds, under the metric it plans.

## What a plan is

A plan is its own QUERY aspect, one per plan, the way a metric is one
QUERY aspect per concept. Its declaration carries `x-kind: plan` and
`x-plan-of`, the metric it plans; its gloss is a grounding like a
metric's, SQL over the landed table, validated by the standard
grounding schema:

```glossql
DECLARE ASPECT revised_budget WITH $${
  "title": "Revised budget",
  "description": "The adopted budget with the council's amendments, as booked",
  "x-kind": "plan", "x-plan-of": "expense", "x-covers": "year", "x-unit": "USD"
}$$ AS QUERY;

GLOSS revised_budget ON brla AS $${
  "sql": "SELECT fiscalmonth AS date, revisedbudget AS value, fund, segment2 FROM expense_budget"
}$$;
```

The tie is judged at read: `x-plan-of` must name a declared QUERY
aspect of the dataset that is not itself a plan, and the plan must
serve the columns named as that metric's period and value, or
`period` and `value`. `metric_axes()` lists the plan with its verdict
and the road out, `plan_of` naming the metric.

A row covers its own period: a monthly schedule plans each month it
names, and the plan covers the months it has rows for. Where a row's
value is booked against a coarser period, the declaration says so:
`x-covers` names the grain, `year` or `quarter`. Baton Rouge books the
adopted budget on the January row and each amendment on the row of its
month, so its budget carries `"x-covers": "year"` and reads at the
year; a month's cell is what was booked that month. A word that is no
grain is refused at `DECLARE`.

An edition of a plan is an aspect of its own: the adopted budget and
the amended budget both stand, each with its own grounding and
assumptions, its own slot under the supersession key and its own
witness if wanted. A re-gloss corrects one edition's SQL; a human's
gloss retires an agent's.

## The read

The plan's grounding stands as a view under the plan's name, like a
metric's. The plan is read through the metric it plans: its period
and value are the columns named as that metric's, its behaviour the
metric's, its floor the grain its rows are booked against where the
declaration says so, else its rows' cadence. Nothing is glossed on a
plan's own columns. `metric_series(world := 'plan', plan :=
'revised_budget')` serves the cells with `metric` the metric the plan
names and `world` `plan`, at the plan's own grain or at any coarser
grain asked; a flow sums, a stock keeps the last level. A finer grain
serves no rows. The actual world never carries a plan's cells, and the
walk and the forecast do not read it.

A variance against the plan is a join of two worlds on metric and
period: the actual at `grain := 'year'` against the plan at the same
grain, `a.value - p.value`. A forecast against the plan is the same
join with `world := 'forecast'` on one side. Original against revised
is a join of two plan reads. `world := 'plan'` without a name, and a
name that is no plan aspect, are refused with the spelling.

`plan_points()` serves the comparison without the join, for every
plan at once: one row per plan and period at the plan's own grain and
at the year, the plan's number, the actual where the period has begun,
the variance where it is complete, and where the forecast covers the
rest its median with the 80% band — at the metric's own grain the
step's band, at the year the actual to date plus the year to go. The
row says where the plan stands: `landed`, `inside`, `below` or `above`
the band, `open` or `ahead` where no band covers it
([reads](../reference/reads.md)).

The year row of a plan finer than the year says how much of the year
its rows cover, `covers`: `9 of 12 months` where a schedule runs to
September, NULL where the rows cover the year whole. Where they cover
part of it, the plan's number and the actual are over the covered
months, the row is `landed` with its variance once those months are
complete and `partial` while they are not, and no band is read: the
forecast totals a year to go, never part of one. A plan booked against
the year, `x-covers: year`, reads at the year alone.

```sql
SELECT plan, label, value, actual, expected, low, high, stands
FROM plan_points() WHERE grain = 'year' ORDER BY plan, period
```

## The judgement

`metric_plan` judges a plan: `SELECT metric_plan() FROM brla.revised_budget`
lands the rows `plan_points()` serves for it as a measurement on the
plan, with the forecast run it was judged against. The witness
`plan_w` reads the gap off the judgement: red where a banded period
lies below or above the forecast's band, the score the share of banded
periods that do. The judgement is stale once the data or the record it
read moves; a newer forecast asks for it again.

## The planning goal

The next read carries the plan as its own goal, `plan`, beside the
seven others ([reads](../reference/reads.md), `next`). Every arm reads
the record, never the data. Its route is the plan's preconditions in
order: an applicable metric, else blocked; the first plan to declare,
its form filled with the dataset and the names left to the author; a
declared plan to ground or stop; a plan the read refuses, to re-record;
the forecast to run, never run or stale; the plan to judge, never
judged or judged against an older forecast. Then every plan year whose
band does not hold the plan is a gap. For a gap with nothing recorded
on it the act is a scenario on a lever, the lever glossed and the
scenario declared with its factors, or the gap recorded at once; with
a scenario standing, the act is the estimate, `metric_scenario`, never
run or stale, then the comparison read, `plan_points()` for the plan's
row beside `scenario_points()` for the estimate and the service's word
on the lever, and the decision. Either way what follows is the same
statement: the decision as an assumption under the key `plan-<year>` in
the plan's own grounding body, at confidence 0.7. The console asks the
human; while the question stands the goal is blocked, and a ruling
under that key closes it. With no gap, the goal is done.

The goal judges the year. A budget booked by the month, the adoption
in January and an amendment in May, means nothing month by month and
something at the year, and the year to go is the total the forecast
asks for a month or a quarter metric. A plan on a week or a day metric
has no year to go; its year rows stand open, and the goal has no gap
to judge. A plan whose rows cover part of a year stands `partial` at
the year, and the goal has no gap there either: its own months hold
their bands.

## Grain

A budget often comes at a coarser grain than the actual: a year's
number beside monthly spend. The plan's grounding serves the date
column as it stands, and the read buckets it as it buckets any flow. Where a budget is booked in the month it was authorized, the
adoption in January and an amendment in May, the plan's month cells
are what the ledger booked that month, and the year is where the plan
means something; the declaration says so, `x-covers: year`, and the
read serves the year. A phased budget, a twelfth a
month or a seasonal curve, is a planner's own table, read at month
grain. The engine spreads nothing.

## Behaviour and grain

A metric's temporal behaviour is how its number combines over time. A
flow adds up: spend, revenue. A stock is a level at a moment: headcount,
inventory; at a coarser grain the read keeps the last level. A ratio
is a quotient: margin, win rate; at a coarser grain the read re-divides
the summed halves. The forecast runs at the metric's own grain and
gives a band for every period ahead, whatever the behaviour. It asks
for a total to go, the quarter or the year, only on a flow: a total of
a stock or a ratio is not a number ([forecast](forecast.md)). That
decides what a plan compares to.

| metric's grain | behaviour | plan at the metric's grain | plan at a coarser grain, or the year row |
|---|---|---|---|
| day | flow | a band per day, 31 ahead | the month to go only |
| day | stock | a band per day | the period's last day's band, within 31 days |
| day | ratio | a band per day | no band |
| week | flow | a band per week, 13 ahead | the quarter to go only |
| week | stock | a band per week | the period's last week's band, within 13 weeks |
| week | ratio | a band per week | no band |
| month | flow | a band per month, 12 ahead | the quarter and the year to go |
| month | stock | a band per month | the period's last month's band, within 12 months |
| month | ratio | a band per month | no band |
| quarter | flow | a band per quarter, 4 ahead | the year to go |
| quarter | stock | a band per quarter | the year's last quarter's band, within 4 quarters |
| quarter | ratio | a band per quarter | no band |
| year, hour, minute | any | no forecast | no band |

A plan at the metric's own grain compares to the band for that period,
for every behaviour. A plan at a coarser grain compares, on a flow, to
the actual to date plus the total to go, and on a stock to the band
for the last period of the metric's own grain inside it: a year-end
headcount against December's forecast, with nothing added, where the
horizon reaches it. A ratio at a coarser grain has no band: a year's
margin is neither a sum nor a last level. A plan at a coarser grain
compares only where its rows cover the period whole; where they cover
part of it, the row carries `covers` and no band. Where the table says
no band, `plan_points()` still serves the row with the actual and the
variance, and `stands` says `open` or `ahead`. The planning goal reads
the year rows, so it finds a gap on a flow at month or quarter grain
and on a stock whose year end the forecast reaches. A margin target is
landed as one row for the month it is due, and the read compares it to
that month's band.

The read compares totals. A budget split by department is a plan per
department, each its own aspect with a filter in its grounding.

## Limits

- One plan aspect serves one metric's numbers. A budget file of many
  lines is read by one plan aspect per line and edition, each
  grounding a filter on its line.
- The plan's behaviour is its metric's: a budget for a stock keeps its
  last level at a coarser grain, like the stock.
- A metric whose grounding is stopped leaves its plans standing. The
  stop is the metric's own `metric_axes()` row.
- A plan's table is no edge of the actuals. A flow's empty periods are
  zero cells up to the data's edge, the latest period the metrics'
  groundings serve; a budget landed through the year's end stretches no
  metric, and the forecast's origin stays the last period with an
  actual. The plan's own cells reach its own frame's end.
- The plan's cells are read from its view at read and move when the
  plan's table or its grounding does. The judgement, `metric_plan`, is
  what the record holds.
