# Bands — expectation ranges from a forecast service

`metric_bands` walks each grounded metric's recent months and
computes, for every walked point, the range that month should have
landed in given everything before it. It runs at dataset grain
(`SELECT metric_bands() FROM fin`) and reports per point the band
quantiles (p05–p95) and the PIT — the quantile at which the actual
landed in the model's own distribution, 0..1 and ordinal by
construction — and the service's verdict over the walk. The witness
`bands_w` carries the verdict; the measurement reports.

## Why a forecast service

With 1–2 years of monthly history, a curve fitted to the series
cannot produce bands that mean what their nominal coverage claims. A
pretrained forecast model conditions on the series as it stands, and
the PIT construction is its own check: if the bands are calibrated,
PITs are uniform; systematic drift shows up as mass at the edges,
which is what the detector scores. The service measured its coverage
one period ahead at 0.78 to 0.84 for a nominal 0.80 on monthly and
weekly data, held-out sets included.

## Mechanism

The kit owns the calendar and sends complete months only.
`band_series()` reads every applicable metric's total at month grain;
a month the data's edge falls inside is left out where rows land
finer than monthly, since a short sum against a corridor fitted on
whole months reads as a breach that is only the calendar.
`band_request()` says per metric whether the walk can take it: seven
complete months at least, so that one origin has the six known values
the service needs. `band_body()` is the request as the service's
contract spells it — every metric's monthly series as one table, the
metric as `member`, the month as `period`, one `value` column — with
the specification `{"targets": ["value"], "origins": 6, "horizon": 1,
"levels": [0.05, 0.1, 0.5, 0.9, 0.95]}` and the witness's threshold as
the walk's red line. The service takes each of the last six months as
an origin, forecasts the month after it from the history up to the
origin, and answers one row per metric, walked month and level, with
the actual and the PIT; the bands are the model's own, and the
service reads no record. A metric with fewer months than a full walk
walks the origins it has; one the service cannot walk is inapplicable
in the service's own words.

The verdict is the service's: displacement is `|2·pit − 1|` — 0.0 at
the median, 0.8 at a nominal-80 edge — and the score is the worst
displacement across the latest point of every metric walked, raised
to the number of metrics scored, so the edges' base rate holds at any
metric count; the band reads the score against the threshold. The
witness's detector repeats the verdict over the measurement's own
voice, so that `ATTEST()` carries it and the checks goal routes on it.

## The record

The PITs of every walk land with the measurement, one per metric and
month, with the share of walked points inside the 80% and the 90%
band, and `band_points()` serves them as rows; `band_verdict()` the
newest verdict. How good past forecasts were is read from the record,
never from the service.

## Serving the model

The server carries no model. The walk's call goes to the model
service's bands route, the service named once for the instance,
`GLOSSDB_SERVICE_URL` ([install](../start/install.md)), as JSON each
way. Without it the walk refuses by name. Every answer names the
service and its version, and the measurement records it as
`served_by`.

## Limits

- Bands inform; they never verdict. Whether a movement is surprising
  is the actor's judgment, informed by the evidence.
- A series that repeats values — a ratio over a fixed field, a count
  — moves on a grid, and the smallest gap between two of its values is
  its resolution. A corridor narrower than that, with the actual
  inside one step of the median, is the model's noise around a value
  the series takes exactly; the point serves its band and actual and
  withholds the PIT, `withheld` naming why, and the detector reads
  nothing breached. An actual further off than a step keeps its PIT:
  that move is real whatever the corridor's width. A series that never
  repeats has no grid, and a tight corridor on it is valid.
- The walk covers the six most recent months, and a walked point
  conditions on at least six known values before it — a metric with
  too short a history is served inapplicable with the reason, and one
  shorter than a full walk walks the origins it has.
- The record is the dataset's, every metric's PITs together. A record
  older than a re-grounding still counts; the drift it carries is what
  the detector reads.
- A month the data's edge falls inside is not sent where rows land
  finer than monthly: its short sum against a corridor fitted on
  whole months reflects the calendar, not a move. A monthly-dated
  series is whole at its one row.
- A NULL date is no period: the rows it dates bucket nowhere.
