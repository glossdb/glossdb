# The harness plan

glossdb's surface works: agents load data, write views and apps, and
the review loop (an assumption, a person's decision, the definition
recorded again) is the strongest part, with the history behind it.
What is weak is the guidance. `next` is a ladder of steps per goal
built on coverage rules, so it counts chores (a meaning on every
column a metric reads) and misses what breaks a number (a join that
fans out, an effective-dated table joined without its dates). Agents
and people cannot tell what can be done, why, or when.

This plan moves that guidance into tests. Kits ship built-in tests on
metrics, written like any team's own: a function that returns a
`breach_rate`, a test that scores it, a person who accepts a result by
recording a tolerance. One read, `metric_tests()`, lists every test on
each metric and on what it reads; `next` and the brief read from it.
No new word: these are data tests. The target is less code and fewer
rules than today, not more.

Today `next` is 56 step arms across `kits/goals`, `kits/metrics` and
`kits/outlook`, plus the brief, review and situation lines built in
`crates/serverd/src/mcp.rs` and `window.rs`.

## The table

| Row | Risk | What it touches | Issue |
|---|---|---|---|
| 1a. Prototype: three built-in tests on metrics (fan-out, how a value combines, orphaned keys) and `metric_tests()` in the metrics kit | Medium | `kits/metrics`, the door suite's test count | built on `metric-tests` |
| 1b. The extension: `glossql_views_scans`, the tables a view scans beside its lineage; `declared_by` on every declaration (`kit:<name>`, or the actor as `kind:id`), so `metric_tests()` tells built-in tests from your own | Medium: a catalog column; existing workspaces need a new one | extension `src/glossql_lineage.cpp`, `src/glossql_store.cpp`, the catalog spec pages; `kits/metrics` | glossql #22, glossdb PR |
| 1c. `next` and the brief read `metric_tests()`: the worst result per metric and the statement that settles it, plus the review queue; the step arms it covers deleted | High: what agents read; the route and door suites assert today's steps | `kits/goals`, `kits/metrics`, `kits/outlook`, `kits/core`, `crates/serverd/src/mcp.rs`, `window.rs` | after 1b |
| 2. Effective-dated tables: a property in the metrics kit (`valid_from`, `valid_to`, the open-end value), and a built-in test for a join that ignores them | Medium | `kits/metrics` | after 1c |
| 3. A metric definition carries its time column, measure with behaviour, and dimensions inline; a person's decision is applied by the server, not re-sent by the agent | Medium: the GLOSS body's schema, `metric_axes()`, the review path | `kits/metrics`, `kits/core`, `crates/duck/src/rulings.rs`, the skills | after 1c |
| 4. The console: a Semantic model view (entities with grain, identity and time axis, relationships, the metrics on them with definitions and decisions) and a Lineage view (sources, load queries, tables, views, metrics at column level, loads over time), linked by object; the Quality section opens on the tests per metric | Medium | `crates/apps/builtin/console/` | after 2 |
| 5. The skills streamlined around the tests: what can be done, why, when, in the prose skill's words | Low | `skills/` | after 1c |

## What the prototype showed

On `hr` (the employees data), with two metrics:

- `staff_by_title` joins `dept_emp` and `titles` on `emp_no` with the
  dates on one side. `fan_out_test` is red, evidence
  `dept_emp.emp_no ~ titles.emp_no`; the metric counts 371,263 people
  on 2002-07-31 against `headcount`'s 240,137.
- `staff_by_title` carries no behaviour on its value: `combine_test` red.
- `headcount` is green on all three; `orphan_test` reads its edge
  `dept_emp.dept_no -> departments.dept_no` at 0 orphans.
- A view's lineage names only the columns that compute its outputs, so
  a check needs the tables it scans too (row 1b).
- A built-in test's property is a FACT a function answers: a
  measurement cannot take a person's tolerance.

## The tests still to write

| Test | Derived from | Settled by |
|---|---|---|
| an effective-dated table joined without its dates | row 2's property on a table the metric scans | the join predicate |
| a placeholder value | a profile's top values or extremes in a date or measure column the metric reads | `column_profile()`, then the load query or an assumption |
| a partial last period | the metric's last period against its table's last load | `temporal()` |
| drift since the last test | a load after a test's last result | the test run again |

## Not in this plan

- Backlog issues: #219 the workspace as code, #220 an optional
  `references` kit, #221 the dbt importer together with reading in
  place.
- A short form for data tests is a language question: a corpus fork in
  the extension, SPEC §9.
- How a bare name resolves when it is both a table of the bound dataset
  and another dataset or a source: a ruling for the lead.
