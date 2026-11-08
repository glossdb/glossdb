---
name: glossql
description: Use glossql through the server's MCP interface — the statements, the shipped reads, the shape of each result, and the engine's sharp edges. Use when reading or writing anything in a glossql workspace (datasets, sources, load queries, annotations, functions, tests).
---

# Speaking glossql

glossql is one SQL-shaped language for a workspace's data and what is
known about it. Data is loaded into tables. What is known is JSON
attached to assets (`table` or `table.column`) under declared aspects:
the properties the harness asks for. The language is `doc://SPEC.md`
and `doc://grammar.ebnf` — read them, don't reconstruct them. Every
`skill://` and `doc://` name is a row of `pages()` — `SELECT body FROM
pages() WHERE uri = '…'` reads one — and a resource for a client that
reads resources. Everything live — the vocabulary, the tables, the
catalog — is read through the language, never assumed. The work
itself — the eight goals and the judgment inside each — is
`skill://glossql-metrics/SKILL.md`.

## The MCP interface

One tool, `glossql`. Its `statements` argument takes a statement or a
semicolon-separated sequence; the result is a JSON array, one outcome
per statement:

- a read — `{"columns": [{"name", "type"}, …], "rows": [...],
  "row_count": n, "truncated": bool}`. `columns` is present even with
  zero rows — a `LIMIT 0` dry run returns the schema. `truncated:
  true` means the result held more than the cap: refine, never read a
  capped result as complete. `GLOSSARY()`, `TESTS()` and the catalog
  tables are uncapped.
- a write — `{"affected": n}` or `{"done": "…"}`. One write answers
  with rows: a `GLOSS` on a VIEW aspect returns the metric's summary
  row in the `metric_axes()` shape — read it before the next write.
- a refused statement — a tool error whose text is the refusal. It
  names what was wrong and, in a sequence, its place: `statement 2 of
  7 refused: … — statement 1 ran; 3–7 not run`, with a
  `{"completed": [...]}` block for what was stored. What was stored stays
  stored.
- two closing lines on every result. `situation:` says whether your
  last statement was done or refused, and for a metric definition
  what its summary row said. `next:` names one action per goal —
  structure, metrics, slices, bands, checks, app, plan, review —
  each with a link. To move a goal, read its link —
  `next://<dataset>/<goal>` as a resource, or `SELECT * FROM next
  WHERE surface = '<goal>'` through the tool — and send the statement
  it gives you, edited to your judgment; `<…>` marks what only you can
  fill. A blocked goal names what blocks it. None of it is an order:
  the goal is what the person asked for.

Who you are — agent or person — comes with the connection; there is
no BY clause. The dataset comes with the endpoint: on a dataset's
endpoint (`/<dataset>/mcp`) every call opens on it, and its tables and
columns resolve unprefixed. On the workspace endpoint (`/mcp`) a call
opens unbound — **there, open every call that touches a dataset's
names with `USE <dataset>;`** — it binds the statements after it and
expires with the call. A call naming none is workspace-scoped, which
is what `SELECT * FROM datasets` wants; a qualified
`dataset.table.column` reads across datasets from anywhere.

## The statements

| statement | does |
|---|---|
| `USE ops;` | bind the statements after it in this call to a dataset — the way in on the workspace endpoint; a dataset's endpoint opens bound |
| `DECLARE DATASET ops SET (…);` | create a dataset |
| `DECLARE SOURCE erp SET (type: parquet, location: 'root');` | register a source; the location is a root — a directory on the server's machine, or an object-store URL it may read — and globs belong in the load query's SQL; `type` describes the export, the load query's `read_parquet`/`read_csv`/`read_json` picks the reader |
| `PREVIEW erp AS $$sql$$;` | a dry run: run load-query-shaped SQL at the source, loading nothing |
| `DECLARE RECIPE work_orders ON ops FROM erp [SET (key: id)] AS $$sql$$;` | declare a load query: the table the SQL produces is loaded, typed as the SQL types it; a key, a column of the result, makes every import merge by it, and the result carries each key once or the load refuses by name |
| `IMPORT work_orders;` | a data update: the table becomes its load query's result as the source is now, in one commit — new files appended where that is the result, the table replaced whole otherwise, the rows merged by the key where the load query names one; `unchanged` when there is nothing new |
| `DROP TABLE work_orders;` | remove a table — refused while it holds data |
| `DECLARE RELATIONSHIP a.col -> b.col;` | declare a join edge (`<->` both ways); a composite endpoint is a tuple, `a.(x, y) -> b.(x, y)`; both endpoints must be loaded columns |
| `DECLARE ASPECT name WITH $$json-schema$$ AS MEASUREMENT\|FACT\|VIEW [ON TABLE, COLUMN, … [WHEN aspect = 'value']];` | add a property to the vocabulary; the schema is the contract every value is validated against; `ON` is the grain — the asset classes it applies to, absent = all; `WHEN` narrows it to assets whose sibling aspect carries the value |
| `GLOSS aspect ON subject AS $$json$$;` | annotate: write your value for the aspect on the asset; an aspect ON TABLE or ON COLUMN takes only a loaded one; a VIEW aspect is annotated on the dataset (`GLOSS revenue ON fin AS …`), the outcome is the metric's summary row, and the metric definition is then served as a view under the aspect's name (`FROM revenue`) |
| `SELECT … FROM GLOSSARY(subject);` | the collapsed view of what is known, one row per aspect |
| `SELECT … FROM GLOSSARY(subject, all => true);` | every value from every author, raw; `all => true` is the call's second argument, never a WHERE condition |
| `DECLARE FUNCTION f FOR ops\|GLOBAL AS $$body$$ [RETURNS aspect];` | register a function — with `RETURNS` one SQL query the engine plans, without it a detector script; `SELECT script FROM functions` reads the shipped library back as worked examples (`glossql-functions` teaches writing one) |
| `SELECT f() FROM work_orders.duration_min;` | run a measurement — it computes at the read's pin (the versions it reads) and stores a `measurements` row; the same pin serves the row back, `computed` says which happened; a body with a `summary` serves the summary alone, the full body reads back via `GLOSSARY(subject::aspect)` |
| `DECLARE TEST w ON aspect [BY (AGENT, HUMAN)] [DETECTOR f THRESHOLD x];` | declare a test: who may annotate the aspect, and which detector scores their agreement |
| `SELECT … FROM TESTS(subject \| ops::aspect);` | test results: bands and scores; sweeps are WHERE clauses |

There is no ordering statement: send statements in the order you need
them. Schema-altering engine DDL — `CREATE VIEW` included — is
closed: tables come from load queries, and a composite edge is a
tuple. A body is written inside `$$…$$` as is — plain double quotes
inside, nothing escaped — and closes as `}$$;`.

## Reading live state

A fresh workspace is not empty: the kits — the KPI kit's `meaning`,
`role`, `behavior`, `unit`, `dimension`, `entity` and the rest with
their tests, the quality kit's measurements, the metrics kit's
`ladder`, the outlook kit's worlds — are declared at open; read them
back before declaring anything.

- The catalog tables, as plain tables — these columns and no others;
  a guessed column costs a refusal, and `DESCRIBE <name>` serves the
  columns of any readable name, the shipped reads included:
  `glossary (seq, dataset, subject, aspect, actor_kind, actor_id, body,
  snapshot_id, written_at)` · `aspects (seq, name, kind, grains,
  condition, schema, declared_at)` · `tests (seq, name, aspect,
  actors, detector, threshold, declared_at)` · `functions (seq,
  name, scope, script, returns, declared_at)` · `measurements (seq,
  dataset, function, subject, aspect, pin, value, computed_at, reads)`
  · `imports (seq, dataset, table_name, mode, rows, dropped_rows_count,
  lineage, snapshot_id, imported_at)` · `recipes (seq, dataset,
  table_name, source, settings, sql, declared_at)` · `relationships`
  · `sources (seq, name, settings, declared_at)` · `datasets (seq,
  name, settings, declared_at)`. The ones with a `dataset` column
  serve the whole workspace — the binding does not narrow them, so say
  which dataset you mean.
- `GLOSSARY(subject)` — the collapsed read, `(subject, aspect, value,
  band, score, state)`, `state` in `current | stale | contested |
  unassessed`; a contested value is withheld, and a missing value is a
  visible row. A subject is a bare path, never a string:
  `GLOSSARY(orders)`, `GLOSSARY(orders.amount)`, `GLOSSARY(fin::revenue)`
  for one aspect; `TESTS(fin::revenue)` likewise.
  **`GLOSSARY(subject, all => true)` is a different shape**: one row
  per author's value, raw, `(subject, aspect, kind, test, actor,
  body, written_at, current)` — no `value`, no `state`; `current` is
  false for a function's value computed before the last write. `value`
  belongs to the collapsed read, `body` to the raw one.
- `TESTS(…)` — `(subject, aspect, test, band, score, computed_at,
  current, error)`, band in green/yellow/orange/red; `error` carries
  a detector's own failure, nothing withheld.
- the loaded schema: `SELECT table_name, column_name, data_type FROM
  information_schema.columns WHERE table_name NOT LIKE '%$%'` serves
  every column of the bound dataset; `DESCRIBE <name>` serves one
  name.
- ordinary SELECT over tables for the data itself.
- names: an unquoted name folds to lowercase, a double-quoted one keeps
  its case. A column keeps the export's spelling and is reached by it
  either way — `joinedAt`, `PATIENT` and `users."joinedAt"` all reach
  the column, in a read and in a subject alike; only two columns that
  differ by case alone need the quotes. A table is reached as declared:
  `"SearchStream"` if it was declared quoted.

**Shipped reads** — derived relations you select from like any table,
filters in WHERE. `DESCRIBE <read>` serves the columns of any of
them — `DESCRIBE band_points()`, `DESCRIBE metric_series(grain := 'month')` —
and every column's meaning is `doc://docs/reference/reads.md`; a
guessed column costs a refusal. A named argument spells `:=`.

| read | serves |
|---|---|
| `workspace_next` | every goal, what is done and what is open — the counts behind the `next:` line |
| `open_questions` | the review queue: what is open for a person to decide — the rows the MCP interface asks as forms |
| `review_decisions` | the person's review decisions in force, with `folded_in` |
| `open_items` | what waits on an action: a load-query approval, a formula answer, a contested value, a measurement stale or never made, a review decision not yet applied |
| `agent_assumptions` | every assumption you currently disclose |
| `metric_surfaces` | every metric of the bound dataset — `name`, `title`, `kind`, `unit`, `meaning`, `formula`, `grounded`, `stopped` — what the catalog says; the numbers are `metric_series()` and `metric_axes()` |
| `metric_series(grain := 'month')` | the cells — `metric`, `world` (`actual` unless asked; `world := 'forecast'` serves the newest forecast's medians ahead; `world := 'scenario', scenario := '<name>'` the named scenario's estimate; `world := 'plan', plan := '<name>'` the named plan's cells under the metric it plans — a plan is a VIEW aspect declared with `x-kind: plan` and `x-plan-of: <metric>`, defined by SQL over the loaded budget table, one aspect per edition, read at its own grain or coarser), `dimension` (`''` the total), `member`, `period`, `value`, `num`, `den`, `behavior`; the arguments are the grain, the world and the scenario's or the plan's name, a metric is a WHERE filter — never `metric_series('name')`; a variance is a join of two worlds on metric and period; a metric whose value column carries no `behavior` refuses to combine rows, and `unclaimed := 'skip'` lists the rest |
| `metric_axes()` | one row per metric: `metric`, `kind`, `plan_of`, `covers`, `stopped`, `applicable`, `reason`, `period_column`, `value_column`, `numerator`, `denominator`, `cadence`, `floor`, `rung`, `behavior`, `behavior_state`, `dims`, `unranked`, `unadmitted`, `missing` (the annotation each unadmitted column needs), `wanted` (the measurement the row reads and nobody ran), `judged_current`; takes no argument |
| `band_points()` | the stored `metric_bands` walk, one row per metric and walked month — `metric`, `applicable`, `reason`, `behavior`, `walked`, `held_80`, `held_90`, `period`, `actual`, `p05`, `p10`, `p50`, `p90`, `p95`, `pit`, `withheld`, `displacement`, `newest`, `point_seq`, `computed_at`; a red is `WHERE newest ORDER BY displacement DESC`, and `band_verdict()` is the walk's verdict in one row |
| `forecast_points()` | the stored `metric_forecast`, one row per metric and point — `seq`, `metric`, `applicable`, `reason`, `grain`, `origin`, `served_by`, `point_seq`, `step`, `span`, `to_go`, `period`, `p05`, `p10`, `p50`, `p90`, `p95`, `service_80`, `service_90`, `actual`, `actuals`, `computed_at`, `current`, `held_80`, `held_90`, `held_from`; `actual` and `actuals` fill as the periods arrive in the data; `held_80` is how often such a band held — this metric's own history once 30 of its points have arrived at that step, else the dataset's, else the service's held-out share — and `held_from` says which; hand a range out with it |
| `forecast_coverage()` | over every stored forecast where a point has arrived: `metric` (`''` the dataset as a whole), `grain`, `step`, `span`, `to_go`, `points`, `inside_80`, `inside_90` (the counts), `held_80`, `held_90` (the shares) — the rows `held_80` comes from once one reaches 30 points |
| `scenario_points('name')` | the newest estimate cell by cell, `scenario_points(NULL)` every scenario — `scenario`, `metric`, `grain`, `origin`, `applicable`, `reason`, `levers`, `pass` (`estimated`), `step`, `period`, `low`, `value`, `high`, `history_value`, `history_low`, `history_high`, `held_80`, `held_from`, `sign`, `confidence`, `basis`, `explains`, `error`, `served_by`, `computed_at`; a lever is declared on a metric's column, `GLOSS lever ON metric.column AS $${"value": true, "grounds": "…"}$$`, a scenario is a FACT aspect with `x-kind: scenario` annotated with `levers` — per lever the column as `metric.column`, a factor per period (`"2027-01": 1.15`) and a basis; `SELECT metric_scenario() FROM <dataset>` runs the estimate; hand an estimate out with its band and `held_80` |
| `scenario_levers('name')` | what each lever does alone — `scenario`, `metric`, `applicable`, `reason`, `sign`, `basis`, `lever`, `planned_from` (`forecast`, or `held: <why>`), `history_shift`, `history_low`, `history_high` (the lever's own effect over the periods ahead and its 90% interval), `computed_at`; the parts add up to the joint estimate, so read them beside `scenario_points()` when a scenario moves several levers — two that cancel show as two parts of opposite sign |
| `plan_points()` | every plan against the actual and the forecast, one row per plan and period at the plan's own grain and at the year — `plan`, `metric`, `grain`, `period`, `label`, `value` (the plan's), `actual` (where the period has begun; the actual to date for the current one), `variance` (actual minus plan, on a complete period), `low`, `expected`, `high` (the forecast's 80% band and median: the step's at the metric's grain, at the year the actual to date plus the year to go), `planned` (`complete`, `inside`, `below`, `above`, `open`, `ahead`), `held_80`, `held_from`, `origin`; `SELECT metric_plan() FROM <dataset>.<plan>` stores the same rows as the plan's judgement, which the plan goal reads — a `below` or `above` year is the gap to record under `plan-<year>` on the plan's body |
| `metric_sources()` | what feeds each metric definition — `metric`, `field`, `source` (`table.column`), `table_name`, `reason`: per served field the column it descends from, and every table it scans |
| `PREVIEW erp AS $$SELECT file FROM glob('*')$$` | every file under a source's location, listed at the source; `glob('**')` the subdirectories too |
| `app_parts` | apps written as annotations, one row per file (`glossql-apps`) |
| `current_dataset` | the dataset the call is bound to, one row — join it to narrow a workspace-wide read |
| `pages()` | every page this server serves — `uri`, `title`, `body`; needs no dataset |

A shipped name is reserved: it shadows a table and a CTE of the same
name. `open_questions`, `review_decisions` and `agent_assumptions` carry
a `dataset` column, so narrow them yourself; `open_items` and
`metric_surfaces` narrow themselves.

```sql
SELECT r.aspect, r.key, r.stance, r.folded_in FROM review_decisions r
JOIN current_dataset d ON d.dataset = r.dataset ORDER BY r.written_at DESC
```

## The review: questions and decisions

A person's answers arrive while you are away, as **review decisions**
(`review_decision` in the catalog) in the person's own annotation — the
judgment alone, naming your claim by its `key`, never a copy of your
body. The `review` goal on the `next:` line carries every action
that waits on you — a decision to apply, an approved load-query
change, a formula answer, a contested value — and gives you the
statement. A question is served once, through the MCP interface's
forms, and waits; the work goes on and the metric definition stays
yours. A client without forms gets none: read `open_questions` and
relay it in chat, multiple choice with your grounds, then run the
statement the answer names. What a review decision is, what each kind
asks of you, and what the confidence number means:
`references/review.md` — open it before disclosing your first
assumption.

## Measure, then judge — never ask a person for a statistic

Functions over-produce: candidates with evidence, never conclusions.
Verify each against the data and declare only the ones that hold; the
rejects stay in the measurement, visible and undeclared. A question
the functions settle — what a column holds, a date's grain, stock or
flow, which columns join, which axes matter — is your work, and
asking the person for it is asking them to do statistics by hand.
`references/settled.md` maps each question to the function that
settles it; walk it before any question leaves the workspace. A
measurement is called in the SELECT list with its subject in FROM —
`SELECT column_profile() FROM orders.amount` — never as a table function.

What remains askable is judgment: definitions, conventions, business
meaning, a choice between readings, held below full confidence. Prose
shapes the work — the topic, which metrics to build, whether to widen
the import — and forms settle the catalog: assumptions in force to
confirm or correct.

The engine's refusals are exact and name what was wrong. Its SQL
guide at this pin is `doc://vendor/duckdb/sql/…` — a function's name
or signature is a lookup there, never a guess — and what the guide
cannot say about this server is `references/sql-here.md`.
