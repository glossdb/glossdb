# Forecasts

Preview: forecasts need a model service, named by `GLOSSDB_SERVICE_URL`
([configuration](../operations/configuration.md)), and may change.

`metric_forecast` asks the model service, for every applicable metric,
what the periods ahead should be from the last period with an actual.
It runs on a dataset (`SELECT metric_forecast() FROM fin`) and stores,
per metric, the ranges per step and, for a flow, the totals of the
quarter and the year to go. Every run is kept at its origin.

- `forecast_points()` returns the latest run, with the actuals joined
  as they arrive.
- `forecast_coverage()` counts how often actuals landed inside the
  ranges.

## Terms

- **Origin:** the last period with an actual.
- **Step:** one period past the origin.
- **Horizon:** how many steps are asked.
- **Span:** the total of the first so many steps.
- **Level:** a quantile the service returns. The range between two
  levels is where the actual should land that often.
- **Coverage:** the share of actuals that landed inside a range.

## How it works

The measurement reads each applicable metric as a whole: the `''`
dimension at the metric's finest grain ([views and table
functions](../reference/reads.md), `metric_series()`). A forecast
period is a bucket of that series.

It sends one request per grain and set of totals, with columns
`member` (the metric), `period` (the bucket's start), `value` and
`status`. The history goes as `actual` rows, then the horizon's periods
as `forecast` rows with no value. The specification names the target,
the five levels (0.05, 0.1, 0.5, 0.9, 0.95), the grain and the horizon,
and for a flow the totals as spans. `forecast_request()` and
`forecast_bodies()` return the request as it is sent.

The horizon is fixed per grain, where the service measured its
coverage:

| Grain | Horizon | Total asked |
|---|---|---|
| day | 31 | the month to go |
| week | 13 | the quarter to go |
| month | 12 | the quarter and the year to go |
| quarter | 4 | the year to go |

- A total runs from the first period ahead to the end of the quarter,
  year or month that period falls in. It is asked only where it fits in
  the horizon. Two spans of the same length are asked once and returned
  under both names.
- A stock or a ratio has no total.
- These metrics are not applicable:
  - minute or hour metrics, since the service forecasts days and
    coarser;
  - year metrics, which have too few periods;
  - metrics with fewer than six periods, refused before any call;
  - any metric the service cannot forecast, refused in the service's
    own words.

Stored per metric: the origin, the grain, the service and its version
as `served_by`, and per step and span the five quantiles, the period,
and the service's held-out share of actuals inside the 80% and the 90%
range at that grain, step and span (`service_80`, `service_90`, from
the `coverage` field of the service's answer). No actual and no PIT are
stored: neither is known at the origin.

## Reading forecasts

`forecast_points()` flattens the latest run, one row per metric and
point. For every point whose actual the series now has, it joins the
actual and says where it landed:

| Position | Meaning |
|---|---|
| `below` | under p05 |
| `low` | between p05 and p10 |
| `inside` | p10 to p90 |
| `high` | between p90 and p95 |
| `above` | over p95 |

A span's actual is the sum of its periods' actuals, once every one is
known. A flow's empty period is a zero up to the data's edge
([views and table functions](../reference/reads.md)), so its point
lands on zero.

Every point says how often such a range held: `held_80` and `held_90`,
with `held_from` naming whose count it is:

1. the metric's own history, where at least 30 of its points have
   landed at that grain, step and span;
2. else the dataset's history, where it reaches 30;
3. else the service's held-out share.

At 30 points the standard error of a share near 0.8 is 0.07. A range
handed to a person carries this number beside it.

`forecast_coverage()` counts over every stored run: per metric and for
the dataset (`''`), per grain, step, span and the span's name, the
points whose actual has landed, the counts, and the shares inside the
80% and the 90% range. A point's `held_80` and `held_90` come from these
rows once they reach 30 points.

`metric_series(world := 'forecast')` returns the newest run as cells
beside the actuals: per metric, one row per step with the median as
`value`, at the metric's own grain. The actual world is the default, so
a query that names no world sees no forecast rows. Forecast against
actual is a join of the two worlds on metric and period. The plan world
sits beside them ([plans](plans.md)): forecast against plan is the same
join, with `world := 'plan', plan := '<name>'` on the plan's side, at
the plan's grain or coarser. `plan_points()` returns it for every plan
at once: the plan's year against the actual to date plus the year to
go, with how often such a range held.

## Why forecasts store no PIT

[Expected ranges](expected-ranges.md) ask about months that have
already happened. The service holds the whole distribution at that
moment and places the actual in it exactly. A forecast is written
before the actual exists, and only five quantiles are stored. Months
later, those five numbers say which range the actual fell in, not its
exact position. Coverage needs only the range.

## The model service

The measurement calls the model service's forecast route, as JSON both
ways. Without `GLOSSDB_SERVICE_URL` it refuses, saying so.

The service measured its 80% range on held-out data at every step the
horizon asks and for the totals it asks. Every answer carries these
shares per step, span and range (`coverage`), and they are stored with
the points:

| Grain | One ahead | At the horizon | The totals |
|---|---|---|---|
| month | 0.75 | 0.67 at twelve | quarter 0.72, year 0.67 |
| week | 0.81 | 0.80 at thirteen | quarter 0.85 |
| day | 0.79 | 0.74 at thirty-one | the calendar month 0.79 |
| quarter | 0.81 | 0.80 at four | year 0.80 |

Weeks and quarters hold their stated coverage at every step. Months
hold it at none. Days hold it for the nearest three steps and run
narrow beyond.

## Limits

- The ranges are the model's own. Until 30 points have landed at a
  grain, step and span, the service's held-out share is the only
  measure, and `held_from` says so.
- The metric is forecast as a whole, not per dimension member.
- A total's range combines the periods' ranges with one constant per
  grain. For days and quarters the service fitted that constant on the
  same held-out datasets it measured the shares on, the only daily and
  quarterly data available. So the calendar month's 0.79 and the
  year's 0.80 are fits, not independent measurements.
- A second run at the same origin counts once in coverage: the newest
  run at that origin.
