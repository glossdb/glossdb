# The harness plan

glossdb's surface works: agents load data, write views and apps, and
the review loop (an assumption, a person's decision, the definition
recorded again) is the strongest part, with the history behind it.
What is weak is the guidance. `next` is a ladder of steps per goal
built on coverage rules, so it counts chores (a meaning on every
column a metric reads) and misses what breaks a number (a join that
fans out, an effective-dated table joined without its dates).
glossval's bare A/B measured the cost: Sonnet with glossdb ties Sonnet
on plain DuckDB on accuracy, at four times the cost and twice the
turns, and the finish line "nothing open" was reached on no run.

The direction: the guidance is tests. Kits ship built-in tests on
metrics, written like any team's own: a function that returns a
`breach_rate`, a test that scores it, a person who accepts a result by
recording a tolerance. `metric_tests()` lists every test on each metric
and on what it reads; `next` and the brief read from it; the server
runs the built-in tests itself, as CI runs a suite. No new word. The
target is less code and fewer rules than today.

This file is the frame. Each plan beside it holds one road and links
its issues: `docs.md`, the positioning, the results page next;
`gate.md`, the statement gate's move into the engine, then data access
per actor; `lineage.md`, one SPEC wording left; `sources.md`, what
comes in: workbooks, documents, databases and Iceberg, search;
`clients.md` and `chat.md`, how a person reaches a workspace and how a
result reaches the chat, parked until the trial.

## The table

| Row | Risk | What it touches | Issue |
|---|---|---|---|
| 1. The outlook's goals as tests: `bands_test` and `plan_test` list under their metric in `metric_tests()`, the judgement statements ride the test rows, and the bands and plan ladders go (24 arms) | Medium: preview; the plan ladder carries the scenario road | `kits/outlook` | next |
| 2. Measured on glossval: the eight A/B seats against the stored bare runs, turns and cost down, finish reached on every run, accuracy held; then the Monday test; the finish prompt says the new finish line | Low | glossval `run.py`, `system/finish.md` | after the pin moves |
| 3. Effective-dated tables: a property (`valid_from`, `valid_to`, the open-end value) and a test for a join that ignores them; the industry's validity interval, SCD type 2 | Medium | `kits/metrics` | after 1 |
| 4. A metric definition carries its time column, measure with its additivity, and dimensions inline, in the shape of Apache Ossie's semantic model (a dataset's fields with `dimension.is_time`, metrics as expressions, relationships, `ai_context`), so an export is a projection and #41's non-additive marker has its place; a person's decision is applied by the server, not re-sent by the agent | Medium: the GLOSS body's schema, `metric_axes()`, the review path | `kits/metrics`, `kits/core`, `crates/duck/src/rulings.rs`, the skills | after 1; #41 |
| 5. The console: the Quality section opens on `metric_tests()`; the Model page shows each metric's definition, decisions and tests; the Lineage page at column level, loads over time | Medium | `crates/apps/builtin/console/` | after 1 |
| 6. The skills streamlined around the tests: what can be done, why, when, beyond the `next:` paragraphs already changed | Low | `skills/` | after 2 |

## What stands

- `next` is the test report: one goal per served metric, named by the
  metric, whose step is its worst test (red, orange, yellow, unassessed)
  with the statement that settles it; then `review`; the outlook's
  `bands` and `plan` only where a model service is named. The
  structure, metrics, slices, checks and app ladders are gone: 56 arms
  became 4 of the metrics kit's, 4 of review, and the outlook's 24
  behind the service. The `next:` line lists what is open and folds
  the done goals into one tail; a dataset with no metric is told so
  once (`kits/metrics`, `kits/goals`, `kits/outlook`,
  `crates/serverd/src/window.rs`, `mcp.rs`).
- The server runs the built-in tests itself, once per call, after the
  statements ran: on every metric the call defined, glossed (the view or
  a column) or whose scanned table it imported, and again on every kit
  check whose result predates a measurement the call made
  (`built_in_tests` in `crates/duck/src/lib.rs`). A failing check is
  logged and never fails the call.
- The checks read stored evidence, never the data again: fan-out from
  the newest `detect_relationships` result, orphans from the newest
  `relationship_coherence` result, and a metric over one table has
  nothing to fan out and no join to check. Evidence not stored yet reads
  yellow with the statement that stores it; a metric scanning two
  tables with no declared edge between them is told to declare it.
- The extension (glossql, branch `contested-two-voices`): a value is
  `contested` only where two actors' values stand; a body that reads
  the `measurements` relation pins the rows of the functions its filter
  names (`function = 'detect_relationships'`), or every function's
  where it names none, one leg per function and never its own or
  another reader's, so a check over stored evidence is served while the
  evidence holds and computes once it moves (SPEC §5.3 and §6, one
  sentence each).
- Three built-in tests on every metric, over the tables its definition
  scans (`glossql_views_scans`): `fan_out_test`, join fan-out;
  `orphan_test`, referential integrity on the declared joins;
  `additivity_test`, whether the value column says how it combines.
  `metric_tests()` lists them with `aspect`, `declared_by` (`kit:<name>`,
  or the actor), `state` and `current`, so a kit's tests and a team's
  own tell apart and a result that predates a change keeps its band. On `hr`:
  `staff_by_title` joins `dept_emp` and `titles` on `emp_no` with the
  dates on one side; fan-out red, evidence `dept_emp.emp_no ~
  titles.emp_no`, additivity red while its value carries no
  behaviour; `headcount` green on all three. Reproduced on a fresh
  workspace at the current pin.
- The `next` view is composed at open from every `routes_<kit>()`
  and hashed (`write_next`); the lowest step decides each goal;
  `window.rs` renders the two lines. The brief counts review decisions,
  approvals and questions. `remeasure` runs every stale or wanted
  function from the console's button; the outlook kit's goals have
  tests (`bands_test`, `plan_test`, `forecast_test`, `scenario_test`)
  for row 1 to list under their metrics.
- A workspace made before a catalog column was added is rebuilt, not
  migrated.

## Cost and caching

What is cached: a measurement by its pin; the `next` view's text by
hash; a kit by its text's hash; the record read, planned once per
store version in the extension. What runs per call: `next` for the
two closing lines, `metric_axes()` behind it, the detectors behind
`TESTS()`. Measured on `hr` on the laptop, two metrics over 331,603
department rows and 443,308 title rows, in seconds per MCP call:

| Call | Seconds |
|---|---|
| `SELECT count(*)` with the two closing lines | 0.40 |
| `SELECT * FROM next` with the two closing lines | 0.73 |
| `SELECT * FROM metric_tests()` with the two closing lines | 0.40 |
| `fan_out_check()` on one metric, first run | 1.36 |
| `additivity_check()` on one metric, first run | 1.09 |
| `orphan_check()` on one metric, first run | 1.10 |

So `next` is about a third of a second of every call, two thirds of
it the bind, which `PREPARE` does not save on DuckLake;
`metric_tests()` reads stored results and costs nothing measurable;
a check costs under a second once and nothing after, so the three
checks the server runs on a definition write cost about three seconds
on this data, and nothing on the data itself, since they read the
stored screen. The checks' reads are `**` (a catalog function), so a
gloss anywhere makes them not current; the server runs them again on
the touched metric only, and on every metric after a measurement, so a
screen run on a dataset of many metrics costs that many checks once.
Row 2 measures before anything else is cached. No cache without a
measured number.

## The tests still to write

| Test | Industry word | Derived from | Settled by |
|---|---|---|---|
| an effective-dated table joined without its dates | validity interval, SCD type 2 | row 6's property on a table the metric scans | the join predicate |
| a placeholder value | sentinel value | a profile's top values or extremes in a date or measure column | `column_profile()`, then the load query or an assumption |
| a partial last period | freshness, incomplete period | the metric's last period against its table's last load | `temporal()` |
| drift since the last test | stale test | a load after a test's last result | built: `current` in `metric_tests()`, run again by the server |
| a value that does not add up from its members | non-additive measure | the definition's aggregate (#41) | row 7's marker |

## Not in this plan

- Backlog issues: #219 the workspace as code, #220 an optional
  `references` kit, #221 the dbt importer together with reading in
  place; an export of the semantic model as Ossie follows row 7.
- A short form for data tests is a language question: a corpus fork in
  the extension, SPEC §9.
- How a bare name resolves when it is both a table of the bound dataset
  and another dataset or a source: a ruling for the lead.
