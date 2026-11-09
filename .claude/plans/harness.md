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
| 1. `next` is the test report: per served metric the worst test, its evidence and the statement that settles it, plus the review queue; the structure, metrics, slices, checks and app ladders go (28 of 56 arms) | High: what agents read; four route tests and about twenty door assertions, two skills, the next-steps page and glossval's finish prompt say today's shape | `kits/goals`, `kits/metrics`, `kits/core`, `crates/serverd/src/window.rs`, `mcp.rs`, `skills/`, `docs/extending/next-steps.md` | drafted below |
| 2. The server runs the built-in tests: after a metric definition's write on that metric, after an import on every metric that scans the table; the situation line carries the worst | Medium: a write's latency; needs row 3 | `crates/duck/src/lib.rs` (`grounding_row`, `remeasure`), `kits/metrics` | with 1 |
| 3. Checks read stored evidence, never the data again: fan-out from the stored relationship measurement, orphans from the stored coherence result, `unassessed` with the statement that produces either when none exists | Low | `kits/metrics` | with 1 |
| 4. The outlook's goals as tests: `bands_test` and `plan_test` list under their metric in `metric_tests()`, the judgement statements ride the test rows, and the bands and plan ladders go (24 arms) | Medium: preview; the plan ladder carries the scenario road | `kits/outlook` | after 1 |
| 5. Measured on glossval: the eight A/B seats against the stored bare runs, turns and cost down, finish reached on every run, accuracy held; then the Monday test | Low | glossval `run.py`, `system/finish.md` | after 1 |
| 6. Effective-dated tables: a property (`valid_from`, `valid_to`, the open-end value) and a test for a join that ignores them; the industry's validity interval, SCD type 2 | Medium | `kits/metrics` | after 1 |
| 7. A metric definition carries its time column, measure with its additivity, and dimensions inline, in the shape of Apache Ossie's semantic model (a dataset's fields with `dimension.is_time`, metrics as expressions, relationships, `ai_context`), so an export is a projection and #41's non-additive marker has its place; a person's decision is applied by the server, not re-sent by the agent | Medium: the GLOSS body's schema, `metric_axes()`, the review path | `kits/metrics`, `kits/core`, `crates/duck/src/rulings.rs`, the skills | after 1; #41 |
| 8. The console: the Quality section opens on `metric_tests()`; the Model page shows each metric's definition, decisions and tests; the Lineage page at column level, loads over time | Medium | `crates/apps/builtin/console/` | after 4 |
| 9. The skills streamlined around the tests: what can be done, why, when; the `next:` paragraphs change with row 1, the rest after | Low | `skills/` | with 1, then after 5 |

## What stands

- Three built-in tests on every metric, over the tables its definition
  scans (`glossql_views_scans`): `fan_out_test`, join fan-out;
  `orphan_test`, referential integrity on the declared joins;
  `additivity_test`, whether the value column says how it combines.
  `metric_tests()` lists them with `declared_by` (`kit:<name>`, or the
  actor), so a kit's tests and a team's own tell apart. On `hr`:
  `staff_by_title` joins `dept_emp` and `titles` on `emp_no` with the
  dates on one side; fan-out red, evidence `dept_emp.emp_no ~
  titles.emp_no`, additivity red while its value carries no
  behaviour; `headcount` green on all three. Reproduced on a fresh
  workspace at the current pin.
- `next`: 56 arms (core 20, metrics 12, outlook 24), composed at open
  into one view whose text is hashed (`write_next`); one row per goal,
  the lowest step deciding; `window.rs` renders the two lines. The
  brief counts review decisions, approvals and questions.
- Mechanisms to build on: a metric definition's write already reads
  its row back (`grounding_row`); `remeasure` runs every stale or
  wanted function from the console's button; a measurement is stored
  with the versions it read and served from the store while they
  hold; the outlook kit's goals already have tests (`bands_test`,
  `plan_test`, `forecast_test`, `scenario_test`).
- A red built-in test reads as a review conflict today: the extension
  marks a value `contested` whenever its detector's score crosses the
  threshold, with one value as with two, against SPEC §7's rule that
  the values must differ (glossql #24). So the review goal says "read
  the contested value on staff_by_title" where the test report should
  say "fan-out red". Row 1 needs that fix, or it inherits the wording.
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
a check costs under a second once and nothing after, so row 2's three
checks on a definition write cost about three seconds on this data.
On millions of rows the fan-out check's relationship screen is the
sharp edge (glossql #10), which row 3 removes by reading the stored
screen. Row 1 shortens the bind by cutting arms; row 5 measures
before anything else is cached. No cache without a measured number.

## The tests still to write

| Test | Industry word | Derived from | Settled by |
|---|---|---|---|
| an effective-dated table joined without its dates | validity interval, SCD type 2 | row 6's property on a table the metric scans | the join predicate |
| a placeholder value | sentinel value | a profile's top values or extremes in a date or measure column | `column_profile()`, then the load query or an assumption |
| a partial last period | freshness, incomplete period | the metric's last period against its table's last load | `temporal()` |
| drift since the last test | stale test | a load after a test's last result | the test run again |
| a value that does not add up from its members | non-additive measure | the definition's aggregate (#41) | row 7's marker |

## Issue, drafted (row 1)

### `next` is the test report per metric

- **What it buys.** An agent and a person read the same thing after
  every call: per served metric, the worst test, its evidence and the
  statement that runs or settles it; then what waits in the review
  queue. Done means every served metric green or accepted and nothing
  waiting on the agent. glossval's finish line becomes reachable, and
  the goals the brief never asked for stop costing turns.
- **What is there.** `routes_core()` (`kits/goals/kit.sql`),
  `routes_metrics()` (`kits/metrics/kit.sql`) and `routes_outlook()`
  (`kits/outlook/kit.sql`) serve 56 arms; `next_view` composes them
  (`crates/duck/src/lib.rs`); `window.rs` renders `situation:` and
  `next:`; `metric_tests()` lists every test per metric with `run`.
  The route suite (`crates/serverd/tests/suite/routes.rs`) and the
  door suite assert the goals' rows and the line's strings.
- **Done when.** `next` has one arm over `metric_tests()` and the
  review's three; the structure, metrics, slices, checks and app arms
  are gone; `next:` reads `<metric> → <test> <state> (next://…)` per
  served metric with a red, unassessed or stale test, `review → …`
  where a decision waits, and `done` otherwise; the `next://` page
  carries the evidence and the statement; the brief's line names the
  red tests; the two skills, the next-steps page and the MCP reference
  say the new shape; the route and door suites hold it; the metrics
  kit's suite covers the three built-in tests and `metric_tests()`.

## Not in this plan

- Backlog issues: #219 the workspace as code, #220 an optional
  `references` kit, #221 the dbt importer together with reading in
  place; an export of the semantic model as Ossie follows row 7.
- A short form for data tests is a language question: a corpus fork in
  the extension, SPEC §9.
- How a bare name resolves when it is both a table of the bound dataset
  and another dataset or a source: a ruling for the lead.
