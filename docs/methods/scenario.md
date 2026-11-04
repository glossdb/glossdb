# The scenario world

A scenario asks what the metrics do if a lever moves, or several. The
model service answers from the history, and the answer lands as a
measurement, `metric_scenario`. `metric_series(world := 'scenario',
scenario := '<name>')` serves the estimate's cells beside the actual
and the forecast worlds; `scenario_points('<name>')` serves the
detail; `scenario_levers('<name>')` serves what each lever does alone.

## What a scenario is

A lever is a column of a metric's view that someone sets: a list
price, a discount rate, a promotion flag. It is glossed on the column,
witness-free, with who sets it; `false` says it was looked at and
nobody does, and a column with no lever gloss is no lever:

```glossql
GLOSS lever ON net_sales.unit_price AS $${"value": true, "grounds": "the list price, set by sales operations"}$$;
```

A scenario is one FACT aspect per scenario with `x-kind: scenario`,
the way a metric is one QUERY aspect per concept. Its body names
declared levers as `<metric>.<column>`, a factor per period on each,
and the basis:

```glossql
DECLARE ASPECT price_hike WITH $${
  "title": "Price +15% from January 2027", "x-kind": "scenario",
  "type": "object", "required": ["levers"],
  "properties": {"levers": {"type": "array"}}
}$$ AS FACT ON DATASET;

GLOSS price_hike ON fin AS $${"levers": [
  {"column": "net_sales.unit_price",
   "factor": {"2027-01": 1.15, "2027-02": 1.15, "2027-03": 1.15},
   "basis": "the price list the board approved"}
]}$$;
```

A period is `YYYY-MM`, a calendar month, or `YYYY-MM-DD`, a day. A
period the body does not name keeps a factor of one. `scenarios()`
judges every scenario declared: glossed, each lever a glossed lever on
a served metric's column, the factor a map. Supersession is the usual
key: a re-gloss updates the scenario, and a human's gloss retires an
agent's. A re-gloss of a metric's view retires the glosses on its
columns, the lever's among them, by the record's stale rule.

## The reach

`scenario_request()` says how far a scenario reaches: one row per
scenario and metric whose view carries one of its levers, with the
metric's floor, its origin (the last actual), its history, the periods
ahead up to the end of the last period the scenario names, and per
lever its series, the mean of the column per period. A scenario
applies to a metric with 26 periods of history and a period ahead,
where an input moves: a lever held at nothing, or factors of one,
move nothing, and the service refuses a request where no input
differs, so the kit judges that before any call.

## The estimate

For the periods ahead the kit asks the model service's what-if route
for every metric reached. First it forecasts each lever on its own,
one forecast call per scenario, metric and lever, the lever's series
as the member and the periods ahead as the horizon: the medians are
the planned input, the last median held past the forecast's reach.
Where the service refuses the lever's forecast, the lever's last value
is held, and the record says so per lever (`planned_from`). Then it
sends the what-if request: the metric's history as actual rows, the
periods ahead twice, as planned and under the scenario, planned times
the period's factor, every lever an input column named as the scenario
names it. `lever_bodies()` and `scenario_bodies()` serve the requests
as they are sent.

The service answers the model's quantiles under the scenario, a sign,
a confidence and a basis, with the history's own reading beside them.
The estimate lands as `metric_scenario`, a measurement on the dataset
over every scenario glossed, with its witness `scenario_w`: owed while
none has landed, owed again once the data or the record it read moves,
which a new scenario gloss does.

A cell of the scenario world is `estimated`. Its value is the median,
`low` and `high` the model's 10 and 90 levels, `history_value`,
`history_low` and `history_high` the history's reading with its 90%
interval, and `held_80` and `held_from` say how often such a band held
at that grain and step by the forecast service's count. Where the
service gives no band, the sign and its basis stand alone.

Several levers are read as one change. The service's reading of the
history adds what each lever does, from the one regression that holds
every lever, and states the sign for the joint change; a lever that
fails a check, or a combination the history never held together, is
named in the basis and no sign is stated. `scenario_levers('<name>')`
serves the parts: per metric and lever, what that lever alone does
over the periods ahead as the mean shift with its 90% interval, so
the parts add up to the joint estimate and two levers that cancel show
as two parts of opposite sign.

## The measured verdict

The service's what-if route promises a direction, not a size. On
3,737 tested series where the history showed an input moving a
column, the model agreed with the history's direction on 94%. The
size was within half to one and a half times the history's on 47%
and under half of it on another 47%. The service's what-if page
carries the tests and the four assumptions under which a lever's
effect reads.

## Limits

- The lever's series is the mean of the column per period. A lever
  whose meaning is a sum reads as a mean; the factor scales both the
  same way.
- No grounding is replayed over the data. The scenario world is the
  estimate ahead of the last actual, and the periods that have landed
  are the actual world's.
- The estimate is the model's reading of the metric's history against
  the lever's. A factor that pushes the lever past what the history
  holds is answered without a sign, and the basis says so.
- An interaction between levers is not read: a promotion working
  differently at a lower price. The history's reading adds the levers'
  effects; a model that read an interaction would disagree with it,
  and the route states no sign.
- The service is called once per estimate: one forecast call per
  lever, one what-if call per scenario and metric. The record keeps
  the newest estimate.
