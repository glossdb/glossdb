# Views and table functions

Every workspace serves these. The catalog's views are declared at
every open; the kits' table functions load with the kits; `owed` and
`next` belong to the server. Each is SQL over the catalog and the lake,
and the same SQL answers the MCP interface, the console and the
skills' examples.

Common rules:

- Filter with `WHERE` and order at the call site; nothing here sorts
  its rows.
- A table function's named arguments use `:=` and come in any order.
- Formatting, glyphs and links are the caller's business.
- `open_questions`, `agent_assumptions`, `ruling_entries`, `app_parts`,
  `app_releases` and `workspace_next` cover the whole workspace and
  carry `dataset` on every row; `current_dataset` names the dataset a
  call is bound to. The kits' table functions and `owed` answer for the
  bound dataset and refuse a call bound to none.

## The catalog's views

### current_dataset

The bound dataset: one row, column `dataset`; no row on a call bound to
no dataset. Join it to narrow a workspace-wide view.

### workspace_next

Where the workspace stands on each thing it can be extended with. Not
a task list. Columns: `surface` (`sources`, `tables`, `relationships`,
`aspects`, `claims`, `functions`, `metrics`, `validations`,
`scenarios`, `plans`, `rulings`, `apps`), `how` (the statement that
extends it), `stands` (what exists), `open` (what is unfinished; 0
where nothing can be). A table is open while its load dropped rows.
Every count spans the workspace: the view to read first, with no
dataset bound.

### open_questions

The review queue: what waits for a person to decide. Derived from
`agent_assumptions`: an assumption with a key, below full confidence,
on a metric definition, in a dimension no function measures
(`behavior`, `sign` and `grain` are statistics), with no review
decision on its (dataset, subject, aspect, key). Columns: `dataset`,
`subject`, `aspect`, `idx`, `dimension`, `key`, `assumption`, `basis`,
`alternative`, `conf`, and `sibling`, `sibling_stance`,
`sibling_note`: a decision the person made on the same key under
another aspect, so the form can offer it again. An `unclear` decision
is never offered.

### agent_assumptions

Every assumption the agent currently states: the latest agent
annotation per asset and aspect, its `assumptions` array one row per
entry, `idx` from 0. Columns: `dataset`, `subject`, `aspect`, `idx`,
`dimension`, `key`, `assumption`, `basis`, `alternative`, `conf`, and
`body`, the whole annotation. Read the extracted columns rather than
`body`. An answered question drops out once the agent records the
definition again with the confidence raised.

### ruling_entries

The person's review decisions, one row per entry of the latest
decision on an asset. Columns: `dataset`, `subject`, `idx`, `aspect`,
`key`, `stance` (`confirmed`, `corrected`, `unclear`), `dimension`,
`assumption` (the text as it was asked; never a join column), `note`,
`written_at`, `folded_in`. `key` names the claim and is the only join
column. `folded_in` is true once no agent assumption below full
confidence carries the decided key under the decided aspect; nothing is
marked done by hand.

### app_parts

Apps written as annotations, one row per file. Columns: `dataset`,
`app`, `path` (`app` for the manifest, `index.html`, `frames/open.sql`,
`specs/series.vl.json`), `text` (the file as written), `actor_kind`.
The newest annotation per asset, aspect and kind of actor, then a
person's over an agent's. This is the draft; the server serves an app
at its release ([app authoring](apps.md)).

### app_releases

What is released of each app, one row per app with a release. Columns:
`dataset`, `app`, `at` (the time the served parts are taken at: the
release's own, or an earlier release its body names), `note`,
`actor_kind`, `released_at` (when the serving release was written; a
later release names it in `at` to return to it). `at` is a reserved
word: quote it, `"at"`.

### metric_surfaces

Every metric of the bound dataset and its state: one row per QUERY
aspect defined here, served or stopped, or named in the `definitions`
glossary. Columns: `name`, `title`, `kind` (the aspect's `x-kind`),
`unit` and `meaning` (from `definitions`), `formula` (from
`definitions`, or the default for a base metric), `grounded` (a
definition with `sql` was written), `stopped` (the stop reason; empty
while it serves). The numbers are in `metric_axes()` and
`metric_series()`; join on `name`.

## The metrics kit

A metric's view is a table of its dataset. Its columns carry roles:
`timestamp` is the period, `measure` the value (the one named `value`
where several are), `dimension` the slices. The `behavior` on the value
column says how a number adds up over periods and members: a flow
sums, a stock keeps its last level, a ratio divides its summed halves,
named `numerator` and `denominator`. The `ladder` on the period column
sets the time grains: `floor`, the finest grain the series is served
at, by default the measured cadence; `windows`, how many whole periods
each grain serves, counted back from the data's edge. Nothing is
recomputed at read: an annotation older than its data is stale, and
the functions return it as the catalog has it.

### metric_axes()

One row per metric of the bound dataset: what its columns are, and
whether a series can be served. Columns: `metric`, `kind` (the
aspect's `x-kind`), `plan_of` and `covers` (a plan's metric, and the
grain its rows are booked at), `stopped` (the stop reason),
`applicable`, `reason` (what to do when it is not), `period_column`,
`value_column`, `numerator`, `denominator`, `cadence` (the period
column's measured grain), `floor` (the ladder's, else the cadence),
`rung` (how many periods the floor serves), `behavior` and
`behavior_state` (the value column's additivity: NULL and `none` where
nobody said, `contested` where the test withholds it), `dims` (the
slicing columns, primary first), `unranked` (dimension columns no
`dimension` annotation ranks), `unadmitted` (served columns with no
role), `owed` (the annotation each of those needs), `wanted` (the
measurement the row reads and nobody ran), `judged_current` (the
profile is at the data's own version).

A plan (`x-kind: plan`) is read through the metric it names. Its
period and value are the columns named as that metric's, or `period`
and `value`; its additivity is the metric's; its floor is the grain its
rows are booked at where the declaration says so (`x-covers`). Nothing
is annotated on a plan's own columns. A served plan's row asks for the
futures kit's `metric_plan` until one exists, as a metric's row asks
for the profile of its period column.

```sql
SELECT metric, applicable, reason, behavior, floor, rung, dims, owed, wanted
FROM metric_axes() ORDER BY metric
```

### metric_series()

```
metric_series(grain := …, world := …, plan := …, scenario := …, unclaimed := …)
```

The cells of every applicable metric of the bound dataset. Columns:
`metric`, `world`, `dimension` (`''` for the total, else a slicing
column), `member`, `period` (a timestamp, the start of the period),
`value`, `num` and `den` (a ratio's summed halves), `behavior`. Without
a grain, each metric at its own floor. With one (`minute` … `year`),
each metric at or below it at that grain; a metric coarser than the
grain asked serves no rows. The floor's window of `n` periods is
served, the period at the data's edge last.

A flow sums, and fills its total's empty periods with zero up to the
data's edge (the last instant any served metric reaches), so a flow
whose rows stopped early shows zeros, not an older window. A stock
keeps the period's last level, summed over what exists at that
instant. A ratio divides its summed halves. A dimension with more than
24 members serves its top 23 by weight and `other`.

No default: where rows must be combined and the value column has no
`behavior`, the function refuses and names the annotation it needs. A
list over every metric passes `unclaimed := 'skip'`: such a metric
serves no cell, and its `metric_axes()` row says what it needs.

`world := 'actual'` is the default: what the definitions compute from
the data. `world := 'forecast'` serves the newest forecast's medians at
the metric's own grain, one row per step; the totals are in
`forecast_points()`. `world := 'scenario', scenario := '<name>'`
serves the named scenario's estimate after the last actual
([scenarios](../preview/scenarios.md)). `world := 'plan', plan :=
'<name>'` serves the named plan's cells under the metric it plans, at
the plan's own grain or any coarser grain asked
([plans](../preview/plans.md)). The worlds' periods do not overlap, so
a variance is a join on metric and period once the actuals arrive;
`plan_points()` serves every plan against the actual and the forecast
without the join.

```sql
SELECT metric, period, value FROM metric_series(grain := 'month')
WHERE dimension = '' ORDER BY metric, period
```

### fact_values()

The single values of the bound dataset: one row per metric whose
aspect declares `x-kind: fact`. Columns: `metric`, `value` where the
view is one row with a `value` column, `reason` where it is not.
Computed at read; nothing is stored.

### metric_sources()

```
metric_sources(for_metric := …)
```

What feeds each metric of the bound dataset, or one, through the
views' lineage: one row per served field and the loaded column it
comes from. Columns: `metric`, `field`, `source` (`table.column`),
`table_name`, `reason`. A computed field (an aggregate, an expression)
comes from no single column and has no row. Beside those, one row per
table the view reads, with `table_name` alone. A view that does not
plan returns one row with `reason`. The console's lineage page draws
this beside the declared relationships.

## The futures kit (preview)

Forecasts, expected ranges, plans and scenarios beside the actual,
answered by the model service the deployment names
(`GLOSSDB_SERVICE_URL`); without one, these measurements refuse by
name and everything else serves. Each result is stored as a
measurement and read back as SQL, so `next` reads the catalog and never
computes over the data. The service owns its subject: the bands, the
PIT and when it is withheld, the walk's verdict, the forecast's
quantiles, the estimate's sign. The kit owns the calendar and sends
complete periods only.

### band_verdict()

The newest walk's verdict, one row, none before a walk: `served_by`
(the service and its version), `grain`, `score`, `band`, `threshold`
(the red line the walk was asked with), `computed_at`.

### band_points()

The newest walk, one row per metric and month walked. Columns:
`metric`, `applicable`, `reason`, `behavior`, `walked`, `held_80` and
`held_90` (the share of walked points inside the 10–90 and the 5–95
band), `period`, `actual`, `p05` … `p95`, `pit`, `withheld`,
`displacement` (|2·pit − 1|, what the detector scores), `newest` (the
latest point walked, the one the verdict scores), `point_seq`,
`computed_at`. A metric not walked returns one row with its reason and
no numbers. This reads the catalog and never runs again: `metric_bands`
walks again and calls the service.

```sql
SELECT metric, period, displacement FROM band_points()
WHERE newest ORDER BY displacement DESC
```

### forecast_points()

The newest forecast, one row per metric and point. Columns: `seq`,
`metric`, `applicable`, `reason`, `behavior`, `grain` (the metric's
floor), `origin` (the last period with a value), `served_by`,
`computed_at`, `current` (whether the measurement is current),
`point_seq`, `step` (periods after the origin), `span` (on a total: the
steps it sums), `to_go` (what a total runs to: `month`, `quarter` or
`year`), `period` (the period forecast; for a total, the one it ends
at), `p05` … `p95`, `service_80` and `service_90` (the service's
held-out share of actuals inside the 80% and the 90% band at that
grain, step and span), `actual` (joined from the actual world at read,
once the period has data; a total's is the sum of its periods, once all
have), `landed` (`below`, `low`, `inside`, `high` or `above` against
p05, p10, p90 and p95), `held_80`, `held_90` and `held_from` (how often
such a band held, and whose count: this metric's own where 30 of its
points have arrived at that grain, step and span, else the dataset's
where it reaches 30, else the service's). A metric the forecast found
not applicable is one row with its reason. The horizon is 31 days, 13
weeks, 12 months or 4 quarters; hours and minutes are finer than the
grains the service measured, a year has too few periods. A flow also
asks for the totals to the end of the month (a day), the quarter (a
week), the quarter and the year (a month), the year (a quarter) that
the first period ahead falls in, where the horizon reaches the span's
end ([forecasts](../preview/forecasts.md)).

### forecast_coverage()

The tally over every forecast of the bound dataset: per metric and for
the dataset (`''` for the metric), per `grain`, `step`, `span` and
`to_go`, where a point has arrived. Columns beside those: `points`,
`inside_80` and `inside_90` (the counts inside p10–p90 and p05–p95),
`held_80` and `held_90` (the shares). `forecast_points()` takes a
point's `held_80` from here once a row reaches 30 points.

### scenario_points()

```
scenario_points(<scenario> | NULL)
```

The newest estimate, one row per scenario, metric and period ahead;
`NULL` returns every scenario. Columns: `scenario`, `metric`, `grain`,
`origin`, `applicable`, `reason`, `levers`, `pass` (`estimated`),
`step`, `period`, `low`, `value`, `high` (the 10, 50 and 90 levels),
`history_value`, `history_low`, `history_high` (the history's own
reading with its 90% interval), `held_80` and `held_from` (the forecast
service's share at that grain and step), `sign`, `confidence`, `basis`
(the service's word on the estimate, or why there is none),
`explains`, `error`, `served_by`, `computed_at`. A metric not
estimated is one row with its reason ([scenarios](../preview/scenarios.md)).

### scenario_levers()

```
scenario_levers(<scenario> | NULL)
```

What each lever of the newest estimate does alone, by the history: one
row per scenario, metric and lever. Columns: `scenario`, `metric`,
`applicable`, `reason`, `sign`, `basis`, `lever` (`<metric>.<column>`),
`planned_from` (`forecast`: the lever's own forecast was the planned
input; `held: <refusal>`: its last value was, and why),
`history_shift`, `history_low`, `history_high` (the lever's own effect
over the periods ahead and its 90% interval), `computed_at`. Two levers
that cancel show as two parts of opposite sign.

### plan_points()

Every served plan against the actual and the forecast, one row per plan
and period at the plan's own grain and, where that is finer, at the
year ([plans](../preview/plans.md)). Columns: `plan`, `metric`,
`grain`, `period`, `label` (the period as text at its grain: `2026`,
`2026-Q3`, `2026-07`, `2026-07-13`), `value` (the plan's cell),
`actual` (the actual cell once the period has begun; for the current
period, to date), `variance` (actual minus plan, on a complete period),
`low`, `expected`, `high` (the newest forecast's 80% band and median:
the step's at the metric's own grain; at a coarser grain, for a flow
the actual to date plus the total to the period's end, for a stock the
band of the last period inside it), `stands` (`landed`: complete;
`inside`, `below`, `above`: where the plan lies against the band;
`partial`: begun, and the rows cover part of the period, so no band;
`open`: begun, no band covers the rest; `ahead`: not begun), `covers`
(on the year row of a plan covering part of the year: `9 of 12
months`), `held_80`, `held_from`, `origin` (the forecast's). Computed
at read. `metric_plan` stores the same rows per plan as a measurement,
which the `plan` goal reads.

### plan_record()

The newest stored comparison per plan, from the measurements alone,
one row per point; the `plan` goal reads this, and `plan_points()`
stays the live view. The columns of `plan_points()` with `plan_grain`,
`forecast_run` (the forecast measurement it was compared against) and
`forecast_origin`.

## A source's files

A file source's files are listed at the source, where a load query's
paths resolve: `PROBE erp_export AS $$SELECT file FROM glob('*')$$`
returns one row per file under the source's location, `glob('**')` the
subdirectories too. A dry run loads nothing.

## The server's views

### owed

What waits on an action in the bound dataset, from the data alone.
Columns: `kind`, `subject`, `what`, `why`, `since`. Six kinds:
`recipe` (an approved load-query change with no load of that table
since), `formula` (a person's formula answer newer than the metric's
recorded definition), `contest` (a value withheld at read: a detector
crossed its threshold or values differ), `re-measure` (a measurement
stored before the last change it read), `never measured` (a measurement
a metric's row reads and nobody ran, or a tested measurement on the
dataset with no result while a metric is defined), `fold-in` (a review
decision whose key is still below full confidence). Each row clears by
the action it names, never by a flag. Refuses a call bound to no
dataset; a workspace with no dataset yet reads `workspace_next`.

### pages()

Every page the MCP interface serves, as rows: `uri`
(`skill://<skill>/SKILL.md`, `skill://<skill>/references/<page>.md`,
`doc://SPEC.md`, `doc://grammar.ebnf`, `doc://docs/…`,
`doc://vendor/duckdb/sql/…`), `title` (the page's first heading),
`body` (the page). The same pages are MCP resources under the same
URIs. `SELECT uri, title FROM pages()` lists them, `WHERE uri = '…'`
reads one. Needs no dataset.

### next

Where the bound dataset stands on each goal, and the one action that
moves it. One row per goal — `structure`, `metrics`, `slices`, `bands`,
`checks`, `app`, `plan`, `rulings` — or the one `WHERE surface = '…'`
names. Columns: `goal` (the goal's order), `surface`, `step`, `state`
(`next`, `blocked`, `done`), `act` (the statement kind, function or
view), `say` (the action in a clause), `why` (what in the catalog
decided), `statement` (the action as a statement, filled from the
catalog; `<…>` marks what only the author can fill) and `then` (what
follows it). How the goals are built and how a kit adds one:
[next steps](../extending/next-steps.md).

```sql
SELECT surface, step, state, say FROM next ORDER BY surface
```

The MCP interface serves the same rows as the resource
`next://<dataset>/<surface>`, and ends every tool result with a
one-line `next:` ([MCP interface](mcp.md)).
