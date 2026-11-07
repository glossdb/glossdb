# Expected ranges

Preview: expected ranges need a model service, named by
`GLOSSDB_SERVICE_URL` ([configuration](../operations/configuration.md)),
and may change.

`metric_bands` walks each metric's recent months. For every month it
walks, it computes the range that month should have landed in, given
everything before it. It runs on a dataset
(`SELECT metric_bands() FROM fin`) and reports, per point:

- the range's quantiles, p05 to p95;
- the PIT: the quantile at which the actual value landed in the
  model's own distribution, from 0 to 1;
- the service's result over the walk.

The test `bands_w` carries the result; the measurement reports.

## Why a forecast model

With one or two years of monthly history, a curve fitted to the series
cannot produce ranges that hold their stated coverage. A pretrained
forecast model works from the series as it is, and the PIT checks it:
if the ranges are calibrated, PITs are spread evenly from 0 to 1;
systematic drift shows as values bunched at the edges, which is what
the detector scores. One period ahead, the service's coverage was 0.78
to 0.84 for a stated 0.80 on monthly and weekly data, held-out sets
included.

## How it works

The kit owns the calendar and sends complete months only.

- `band_series()` reads every applicable metric's total by month. Where
  rows are dated finer than monthly, the month the data ends inside is
  left out: a short sum against a range fitted on whole months reads
  as a breach that is only the calendar.
- `band_request()` says per metric whether it can be walked: at least
  seven complete months, so that one origin has the six known values
  the service needs.
- `band_body()` builds the request in the service's format: every
  metric's monthly series as one table (the metric as `member`, the
  month as `period`, one `value` column), with the specification
  `{"targets": ["value"], "origins": 6, "horizon": 1, "levels": [0.05,
  0.1, 0.5, 0.9, 0.95]}` and the test's threshold as the walk's red
  line.

The service takes each of the last six months as an origin, forecasts
the month after it from the history up to that origin, and answers one
row per metric, walked month and level, with the actual and the PIT.
The ranges are the model's own; the service reads nothing from the
catalog. A metric with fewer months than a full walk walks the origins
it has. One the service cannot walk is returned as not applicable, in
the service's own words.

## The result

The result is the service's:

- **Displacement** is `|2·pit − 1|`: 0.0 at the median, 0.8 at the
  edge of an 80% range.
- **The score** is the worst displacement across the latest point of
  every metric walked, raised to the number of metrics scored, so the
  edges' base rate holds at any number of metrics.
- **The band** reads the score against the threshold.

The test's detector repeats the result over the measurement's own
value, so `ATTEST()` carries it and the checks goal acts on it.

## History

Every walk's PITs are stored with the measurement, one per metric and
month, with the share of walked points inside the 80% and the 90%
range. `band_points()` returns them as rows, and `band_verdict()` the
newest result. How good past forecasts were is read from the catalog,
never from the service.

## The model service

The server carries no model. The walk calls the model service's bands
route, as JSON both ways. Without `GLOSSDB_SERVICE_URL` the walk
refuses, saying so. Every answer names the service and its version, and
the measurement stores it as `served_by`.

## Limits

- Ranges inform; they never decide. Whether a movement is surprising is
  the agent's or a person's judgment, informed by the evidence.
- **Series on a grid.** A series that repeats values (a ratio over a
  fixed field, a count) moves in steps, and the smallest gap between
  two of its values is its resolution. When a range is narrower than a
  step and the actual is within one step of the median, the range is
  the model's noise around a value the series takes exactly. The point
  returns its range and actual, withholds the PIT (`withheld` says
  why), and the detector reads nothing breached. An actual further off
  than a step keeps its PIT: that move is real whatever the range's
  width. A series that never repeats has no grid, and a tight range on
  it is valid.
- The walk covers the six most recent months, and each walked point
  needs at least six known values before it. A metric with too short a
  history is returned as not applicable with the reason; one shorter
  than a full walk walks the origins it has.
- The history is the dataset's: every metric's PITs together. History
  from before a metric's definition changed still counts; the drift it
  carries is what the detector reads.
- Where rows are dated finer than monthly, the month the data ends
  inside is not sent. A series dated by month is whole at its one row.
- A NULL date is no period: the rows it dates fall in no bucket.
