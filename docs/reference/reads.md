# The shipped reads

Every workspace serves these reads. The record's reads are views the
engine declares at open. The kits' reads are table macros, loaded
with the kits. `owed` and `next` are the door's own. Every one is SQL
over the record and the lake; the same SQL answers the doors, the
docket's frames and the skills' examples.

A read is a derived relation. Filter with `WHERE`. Order at the call
site: no read carries an ordering of its own. A table macro's named
arguments spell `:=` and come in any order. Formatting, glyphs and
links are the caller's business.

Scope is the caller's too. `open_questions`, `agent_assumptions`,
`ruling_entries`, `app_parts`, `app_releases` and `workspace_next`
answer for the whole workspace and carry `dataset` on every row: the
question round asks across every dataset from an unbound channel, the
docket asks about the one it is bound to. `current_dataset` names the
bound one. The kits' reads and `owed` answer for the bound dataset and
refuse an unbound call.

## The record's reads

### current_dataset

The bound dataset as a relation: one row, column `dataset`, and no row
on an unbound channel. A read over a workspace-wide relation narrows
itself by joining this.

### workspace_next

What this workspace can be extended through, and where it stands on
each surface. Not a task queue. Columns: `surface` (`sources`,
`tables`, `relationships`, `aspects`, `claims`, `functions`,
`metrics`, `validations`, `scenarios`, `plans`, `rulings`, `apps`),
`how` (the statement that extends the surface), `stands` (what
exists), `open` (what is unfinished; 0 where nothing can be owed). A
table is open while its landing dropped rows. Every count spans the
workspace: the orienting read, run from a channel bound to nothing.

### open_questions

What still stands open for a human to judge. Derived from
`agent_assumptions`, the agent's current body: a keyed assumption
below full confidence, on a grounding, in a dimension no function owns
(`behavior`, `sign` and `grain` are statistics), with no standing
ruling on its (dataset, subject, aspect, key). Columns: `dataset`,
`subject`, `aspect`, `idx`, `dimension`, `key`, `assumption`, `basis`,
`alternative`, `conf`, and `sibling`, `sibling_stance`,
`sibling_note`: a ruling the human gave on the same key under another
aspect, so the form can offer it back. An `unclear` stance is never
offered.

### agent_assumptions

Every assumption the agent currently discloses: the latest agent gloss
per slot, its `assumptions` array one row per entry, `idx` from 0.
Columns: `dataset`, `subject`, `aspect`, `idx`, `dimension`, `key`,
`assumption`, `basis`, `alternative`, `conf`, and `body`, the whole
writing the assumption sits inside. Read the extracted columns rather
than reaching into `body`. An answered question drops out when the
fold-in raises its confidence.

### ruling_entries

The human's standing rulings, one row per entry of the latest ruling
body on a subject. Columns: `dataset`, `subject`, `idx`, `aspect`,
`key`, `stance` (`confirmed`, `corrected`, `unclear`), `dimension`,
`assumption` (the prose snapshot, never a join column), `note`,
`written_at`, `folded_in`. `key` names the claim and is the only join
column. `folded_in` is true once no agent assumption below full
confidence carries the ruled key under the ruled aspect; nothing is
marked done by hand.

### app_parts

Apps authored as glosses, one row per file. Columns: `dataset`, `app`,
`path` (`app` for the manifest, `index.html`, `frames/open.sql`,
`specs/series.vl.json`), `text` (the file as the gloss spelled it),
`actor_kind`. Two collapses in order: the newest writing per (dataset,
subject, aspect, actor kind), then the human's over the agent's. This
is the draft; the door serves the app at its release.

### app_releases

What is released of each glossed app, one row per app that carries a
release. Columns: `dataset`, `app`, `at` (the time the served parts
are cut at: the release's own, or the earlier release its body names),
`note`, `actor_kind`, `released_at` (when the serving release was
written; a later release names it in `at` to return to it). The same
two collapses as `app_parts`. `at` is a reserved word in SQL: quote it,
`"at"`.

### metric_surfaces

Every metric the bound dataset claims, with where it stands: one row
per QUERY aspect a grounding stands on here, served or stopped, or
whose `definitions` entry names it. Columns: `name`, `title`, `kind`
(the aspect's `x-kind`), `unit` and `meaning` (from the `definitions`
handbook), `formula` (from the `formulas` registry, or the stated
base-concept default), `grounded` (a grounding with `sql` was
written), `stopped` (the collapsed grounding's own text, empty where
it serves). The numbers are `metric_axes()` and `metric_series()`;
join on `name`.

## The metrics kit's reads

A grounding's view is a table of its dataset. The column that carries
role `timestamp` is the metric's period, the column that carries role
`measure` its value (the one named `value` where several do), the
columns that carry role `dimension` its slices. The `behavior` on the
value column says how a number combines over periods and members: a
flow sums, a stock keeps its last level, a ratio re-divides its summed
halves, the halves named as `numerator` and `denominator`. The ladder
on the period column says how its periods are walked: `floor`, the
grain the series is served at, by default the measured cadence;
`windows`, the rung per grain, how many whole buckets a read serves,
measured back from the data's edge. Nothing is re-marked at read: a
claim older than its data is stale by the record's rule, and the reads
serve it as the record does.

### metric_axes()

One row per metric of the bound dataset: what the record says its
columns are, and whether a series can be served. Columns: `metric`,
`kind` (the aspect's `x-kind`), `plan_of` and `covers` (a plan's
metric, and the grain its rows are booked against), `stopped` (the
author's text), `applicable`, `reason` (the road out when it is not),
`period_column`, `value_column`, `numerator`, `denominator`, `cadence`
(the period column's measured granularity), `floor` (the ladder's,
else the cadence), `rung` (how many buckets the floor serves),
`behavior` and `behavior_state` (the collapsed claim on the value
column: NULL and `none` where nobody spoke, `contested` where the
witness withholds it), `dims` (the slicing columns, primary first),
`unranked` (the dimension columns no `dimension` gloss ranks),
`unadmitted` (the served columns no role stands on), `owed` (the gloss
each of those wants), `wanted` (the measurement the row reads and
nobody ran), `judged_current` (the profile stands at the data's own
version).

A plan (`x-kind: plan`) is read through the metric it names. Its
period and value are the columns named as that metric's, or `period`
and `value`; its behaviour is the metric's; its floor is the grain its
rows are booked against where the declaration says so (`x-covers`).
Nothing is glossed on a plan's own columns. A served plan's row wants
the judgement the futures kit measures on it, `metric_plan`, until one
stands, as a metric's row wants the profile over its period column.

```sql
SELECT metric, applicable, reason, behavior, floor, rung, dims, owed, wanted
FROM metric_axes() ORDER BY metric
```

### metric_series(grain := …, world := …, plan := …, scenario := …, unclaimed := …)

The cells of every applicable metric of the bound dataset. Columns:
`metric`, `world`, `dimension` (`''` the total, else a slicing
column), `member`, `period` (a typed timestamp, the bucket's start),
`value`, `num` and `den` (a ratio's summed halves), `behavior`.
Without a grain, each metric at its own floor. With one (`minute` …
`year`), each metric at or below it at that grain; a metric coarser
than the asked grain serves no rows. A rung of `n` buckets is served,
the edge's bucket the last.

A flow sums, and fills its total's empty periods with zero up to the
data's edge, the last instant any served metric reaches, so a flow
whose rows stopped early shows its zeros, not an older window. A stock
keeps the bucket's last level, summed over what stands at that
instant. A ratio re-divides its summed halves. A dimension wider than
24 members serves its top 23 by weight and `other`.

The no-claim rule: where rows have to be combined and no behaviour
stands on the value column, the read refuses and names the gloss. It
defaults nothing. A list over every metric asks `unclaimed := 'skip'`:
such a metric serves no cell, and its fact row says what it owes.

`world := 'actual'` is the default, what the groundings compute from
the data. `world := 'forecast'` serves the newest forecast's medians
at the metric's own grain, one row per step; the totals are
`forecast_points()`'s. `world := 'scenario', scenario := '<name>'`
serves the named scenario's estimate ahead of the last actual ([the
scenario world](../methods/scenario.md)). `world := 'plan', plan :=
'<name>'` serves the named plan's cells under the metric it plans
([the plan world](../methods/plan.md)), at the plan's own grain or any
coarser grain asked. The worlds' periods do not overlap, so a variance
is a join on metric and period once the actuals land; `plan_points()`
serves every plan against the actual and the forecast without the
join.

```sql
SELECT metric, period, value FROM metric_series(grain := 'month')
WHERE dimension = '' ORDER BY metric, period
```

### fact_values()

The declared facts of the bound dataset, served whole: one row per
metric whose aspect declares `x-kind: fact`. Columns: `metric`,
`value` where the view is one row with a `value` column, `reason`
where it is not. The data at read; nothing is recorded.

### metric_sources(for_metric := …)

What feeds each metric of the bound dataset, or one, through the
views' lineage: one row per served field and the landed column it
descends from. Columns: `metric`, `field`, `source` (`table.column`),
`table_name`, `reason`. A computed field (an aggregate, an expression)
descends from no column and has no row. Beside those, one row per
table the view reads, `table_name` alone. A view that does not plan
serves one row with `reason`. The docket's lineage tab draws this
beside the declared relationships.

## The futures kit's reads

The worlds beside the actual: the walk's bands and the forecast, each
what the model service answers; the plan, judged against them; the
scenario, the service's estimate. Each lands as a measurement with its
pin and is read back as SQL, so that the door's `next` read judges
from the record and never computes over the data. The service is named
once for the instance (`GLOSSDB_SERVICE_URL`); without one, these
measurements refuse by name and everything else serves. The service
owns its topic: the bands, the PIT and why it is withheld, the walk's
verdict, the forecast's quantiles, the estimate's sign. The kit owns
the calendar and sends complete periods only.

### band_verdict()

The newest walk's verdict, one row, none before a walk: `served_by`
(the service and its version), `grain`, `score`, `band`, `threshold`
(the red line the walk was asked with), `computed_at`.

### band_points()

The newest walk, one row per metric and walked month. Columns:
`metric`, `applicable`, `reason`, `behavior`, `walked`, `held_80` and
`held_90` (the share of walked points inside the 10–90 and the 5–95
band), `period`, `actual`, `p05` … `p95`, `pit`, `withheld`,
`displacement` (|2·pit − 1|, what the detector scores), `newest` (the
latest walked point, the one the verdict scores), `point_seq`,
`computed_at`. A metric not walked serves one row with its reason and
no numbers. The record itself, never a re-run: `metric_bands` walks
again and calls the service.

```sql
SELECT metric, period, displacement FROM band_points()
WHERE newest ORDER BY displacement DESC
```

### forecast_points()

The newest forecast, one row per metric and point. Columns: `seq`,
`metric`, `applicable`, `reason`, `behavior`, `grain` (the metric's
floor), `origin` (the last period with a value), `served_by`,
`computed_at`, `current` (whether the measurement stands at this pin),
`point_seq`, `step` (periods past the origin), `span` (set on a total:
the steps it sums), `to_go` (what a total runs to: `month`, `quarter`
or `year`), `period` (the period forecast; for a total, the one it
ends at), `p05` … `p95`, `service_80` and `service_90` (the service's
held-out share of actuals inside the 80 % and the 90 % band at that
grain, step and span), `actual` (joined from the actual world at read,
where the period has landed; a total's is the sum of its periods,
where every one has), `landed` (`below`, `low`, `inside`, `high` or
`above` against p05, p10, p90 and p95), `held_80`, `held_90` and
`held_from` (how often such a band held, and whose count: this
metric's own record where 30 of its points have landed at that grain,
step and span, else the dataset's where it reaches 30, else the
service's). A metric the forecast found inapplicable is one row with
its reason. The horizon is 31 days, 13 weeks, 12 months or 4 quarters;
an hour or a minute is finer than the grains the service measured, a
year has too few periods. A flow also asks the totals to the end of
the month (a day), the quarter (a week), the quarter and the year (a
month), the year (a quarter) that the first period ahead falls in,
where the horizon reaches the span's end ([forecast](../methods/forecast.md)).

### forecast_coverage()

The record's tally over every forecast the bound dataset holds: per
metric and for the dataset (`''` the metric), per `grain`, `step`,
`span` and `to_go`, where a point has landed. Columns beside those:
`points`, `inside_80` and `inside_90` (the counts inside p10–p90 and
p05–p95), `held_80` and `held_90` (the shares). `forecast_points()`
serves a point's `held_80` from here once a row reaches 30 points.

### scenario_points(scenario)

The newest estimate, one row per scenario, metric and period ahead;
`scenario_points(NULL)` serves every scenario. Columns: `scenario`,
`metric`, `grain`, `origin`, `applicable`, `reason`, `levers`, `pass`
(`estimated`), `step`, `period`, `low`, `value`, `high` (the 10, 50
and 90 levels), `history_value`, `history_low`, `history_high` (the
history's own reading with its 90 % interval), `held_80` and
`held_from` (the forecast service's share at that grain and step),
`sign`, `confidence`, `basis` (the service's word on the estimate, or
why there is none), `explains`, `error`, `served_by`, `computed_at`. A
metric not estimated is one row with its reason ([the scenario
world](../methods/scenario.md)).

### scenario_levers(scenario)

What each lever of the newest estimate does alone, by the history: one
row per scenario, metric and lever. Columns: `scenario`, `metric`,
`applicable`, `reason`, `sign`, `basis`, `lever` (`<metric>.<column>`),
`planned_from` (`forecast`: the lever's own forecast was the planned
input; `held: <refusal>`: its last value was, and why),
`history_shift`, `history_low`, `history_high` (the lever's own effect
over the periods ahead and its 90 % interval), `computed_at`. Two
levers that cancel show as two parts of opposite sign.

### plan_points()

Every served plan against the actual and the forecast, one row per
plan and period at the plan's own grain and, where that is finer, at
the year ([the plan world](../methods/plan.md)). Columns: `plan`,
`metric`, `grain`, `period`, `label` (the period as text at its grain:
`2026`, `2026-Q3`, `2026-07`, `2026-07-13`), `value` (the plan's
cell), `actual` (the actual world's cell where the period has begun;
for the current period, to date), `variance` (actual minus plan, on a
complete period), `low`, `expected`, `high` (the newest forecast's
80 % band and median: the step's at the metric's own grain; at a
coarser grain, for a flow the actual to date plus the total that runs
to the period's end, for a stock the band of the last period of the
metric's grain inside it), `stands` (`landed`: complete; `inside`,
`below`, `above`: where the plan lies against the band; `partial`:
begun, and the rows cover part of the period, so no band; `open`:
begun, no band covers the rest; `ahead`: not begun), `covers` (on the
year row of a plan whose rows cover part of the year, how much: `9 of
12 months`), `held_80`, `held_from`, `origin` (the forecast's).
Computed at read. `metric_plan` lands the same rows per plan as a
measurement, the judgement the plan goal reads.

### plan_record()

The newest judgement per plan from the measurements alone, one row
per point, the read the door's plan arms take; `plan_points()` stays
the live read. The columns of `plan_points()` with `plan_grain`,
`forecast_run` (the forecast measurement it was judged against) and
`forecast_origin` beside them.

## The sources' files

A file source's files are listed at the source, where a recipe's paths
resolve: `PROBE erp_export AS $$SELECT file FROM glob('*')$$` serves
one row per file under the source's location, `glob('**')` the
subdirectories too. A probe runs at the source and lands nothing, so
the listing is the same walk a recipe's `read_*` glob resolves through.

## The door's reads

### owed

What stands waiting on an act in the bound dataset, from the data
alone. Columns: `kind`, `subject`, `what`, `why`, `since`. Six kinds:
`recipe` (an approved recipe change with no landing of that table
since), `formula` (a human formula answer newer than the metric's
recorded grounding), `contest` (a slot withheld at read: a detector
crossed or voices differ), `re-measure` (a function voice landed
before the last change it read), `never measured` (a measurement a
metric's row reads and nobody ran, or a witnessed measurement on the
dataset with no voice while a metric is grounded), `fold-in` (a ruling
whose key still stands below full confidence). Each row resolves by
the act it names, never by a flag. The read refuses an unbound call;
a workspace before its first dataset reads `workspace_next` instead.

### pages()

Every page the door serves, as rows: `uri` (`skill://<skill>/SKILL.md`,
`skill://<skill>/references/<page>.md`, `doc://SPEC.md`,
`doc://grammar.ebnf`, `doc://docs/…`, `doc://vendor/duckdb/sql/…`),
`title` (the page's first heading), `body` (the page, verbatim). The
same pages are the door's MCP resources under the same URIs. `SELECT
uri, title FROM pages()` lists them, `WHERE uri = '…'` reads one.
Needs no dataset.

### next

Where the record stands toward each goal on the bound dataset, and
the one act that moves it. One row per goal, `structure`, `metrics`,
`slices`, `bands`, `checks`, `app`, `plan`, `rulings`, or the one named
by `WHERE surface = '…'`. Columns: `surface`, `step`, `state` (`next`,
`blocked`, `done`), `act` (the statement kind, function or read),
`say` (the act in a clause), `why` (what on the record decided),
`statement` (the act as a statement, filled from the record; `<…>`
marks what only the author can fill) and `then` (what follows it).

A goal's route is its steps in order, one query arm each: an arm
serves a row when its condition holds on the record, and the lowest
step that serves decides the goal. The engine composes the read at
open from every kit's routes: the core's answer `structure`, `checks`,
`app` and `rulings`, the metrics kit's `metrics` and `slices`, the
futures kit's `bands` and `plan`. Every arm reads the record and never
the data: the futures' judgements are measurements, read back. A
statement is a proposal: edit it, send it, or do not.

```sql
SELECT surface, step, state, say FROM next ORDER BY surface
```

The MCP door serves the same rows as the resource template
`next://<dataset>/<surface>`, and carries a one-line `next:` on every
tool result.
