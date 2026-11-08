# Scenarios

Preview: scenarios need a model service, named by `GLOSSDB_SERVICE_URL`
([configuration](../operations/configuration.md)), and may change.

A scenario asks what the metrics do if one or more levers move. The
model service answers from the history, and the answer is stored as a
measurement, `metric_scenario`.

- `metric_series(world := 'scenario', scenario := '<name>')` returns the
  estimate's cells beside the actual and forecast worlds.
- `scenario_points('<name>')` returns the detail.
- `scenario_levers('<name>')` returns what each lever does alone.

## Declaring a scenario

A lever is a column of a metric's view that someone sets: a list
price, a discount rate, a promotion flag. It is annotated on the column,
with no test, saying who sets it. `false` says the column was looked at
and nobody sets it. A column with no `lever` annotation is not a lever.

```glossql
GLOSS lever ON net_sales.unit_price AS $${"value": true, "grounds": "the list price, set by sales operations"}$$;
```

A scenario is one FACT aspect per scenario, with `x-kind: scenario`,
the way a metric is one view aspect per concept. Its body names
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

- A period is `YYYY-MM`, a calendar month, or `YYYY-MM-DD`, a day. A
  period the body does not name keeps a factor of one.
- `scenarios()` checks every declared scenario: annotated, each lever
  an annotated lever on a column of a served metric, the factor a map.
- A new annotation updates the scenario, and a person's annotation
  replaces an agent's.
- A new annotation of a metric's view makes the annotations on its
  columns stale, the lever's among them.

## What a scenario reaches

`scenario_request()` says how far a scenario reaches. It returns one
row per scenario and per metric whose view carries one of its levers,
with:

- the metric's finest grain and its origin (the last actual);
- its history;
- the periods ahead, up to the end of the last period the scenario
  names;
- per lever, its series: the mean of the column per period.

A scenario applies to a metric with 26 periods of history and at least
one period ahead, where an input moves. A lever held at nothing, or
factors of one, move nothing. The service refuses a request where no
input differs, so the kit checks that before any call.

## The estimate

For the periods ahead, the kit asks the model service's what-if route
about every metric reached, in two calls:

1. **Plan each lever.** One forecast call per scenario, metric and
   lever, with the lever's series as the member and the periods ahead
   as the horizon. The medians are the planned input; the last median
   is held past the forecast's reach. Where the service refuses the
   lever's forecast, the lever's last value is held, and the catalog
   says so per lever (`planned_from`).
2. **Ask what-if.** The metric's history as actual rows, then the
   periods ahead twice: as planned, and under the scenario (planned
   times the period's factor), with every lever as an input column
   named as the scenario names it.

`lever_bodies()` and `scenario_bodies()` return the requests as they
are sent.

The service answers with the model's quantiles under the scenario, a
sign, a confidence and a basis, and the history's own reading beside
them. The estimate is stored as `metric_scenario`, a measurement on the
dataset over every annotated scenario, with its test `scenario_test`. It
is due while none has been made, and due again once the data or the
catalog rows it read change, which a new scenario annotation does.

A cell of the scenario world is `estimated`:

| Column | Meaning |
|---|---|
| `value` | the median |
| `low`, `high` | the model's 10 and 90 levels |
| `history_value`, `history_low`, `history_high` | the history's reading, with its 90% interval |
| `held_80`, `held_from` | how often such a range held at that grain and step, by the forecast service's count |

Where the service gives no range, the sign and its basis stand alone.

**Several levers are read as one change.** The service's reading of the
history adds up what each lever does, from one regression that holds
every lever, and states the sign for the joint change. A lever that
fails a check, or a combination the history never held together, is
named in the basis, and no sign is stated. `scenario_levers('<name>')`
returns the parts: per metric and lever, what that lever alone does over
the periods ahead, as the mean shift with its 90% interval. The parts
add up to the joint estimate, and two levers that cancel show as two
parts of opposite sign.

## Accuracy

The what-if route promises a direction, not a size. On 3,737 tested
series where the history showed an input moving a column, the model
agreed with the history's direction on 94%. The size was within half to
one and a half times the history's on 47%, and under half of it on
another 47%. The service's own what-if documentation carries the tests
and the four assumptions under which a lever's effect can be read.

## Limits

- A lever's series is the mean of the column per period. A lever whose
  meaning is a sum reads as a mean; the factor scales both the same
  way.
- No metric definition is replayed over the data. The scenario world is
  the estimate after the last actual; the periods already loaded belong
  to the actual world.
- The estimate is the model's reading of the metric's history against
  the lever's. A factor that pushes the lever past anything in the
  history is answered without a sign, and the basis says so.
- Interactions between levers are not read: a promotion working
  differently at a lower price. The history's reading adds the levers'
  effects; a model that read an interaction would disagree with it, and
  the route then states no sign.
- The service is called once per estimate: one forecast call per lever,
  one what-if call per scenario and metric. The catalog keeps the
  newest estimate.
