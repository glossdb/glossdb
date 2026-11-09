# Next steps

After every call, the agent is told where each served metric stands:
its worst test, the evidence, and the statement that settles it. Then
what a person decided and the agent has not applied. This is the `next`
view, built from the kits. Kits add goals the same way.

## The goals

| Goal | Done when | From |
|---|---|---|
| one per served metric, named by the metric | every test on the metric is green or accepted: no red, none unrun | `metrics` kit |
| `review` | nothing waits: review decisions applied, approved load queries declared again, contested values read | `goals` kit |
| `bands` | the expected-range walk exists and no band is red, or the red carries a question or a review decision (preview; only where a model service is named) | `outlook` kit |
| `plan` | every plan is served and compared, none lies outside the forecast's band, or the gap carries a question or a review decision (preview; only where a model service is named) | `outlook` kit |

A dataset with no served metric gets one row, `metrics`, saying so.
The goal is the caller's: what the person asked for decides which
metric the agent works on. Nothing is stored about it, and no step is
an order.

## The tests behind a metric's goal

The metrics kit ships three tests on every metric, over the tables its
definition scans: `fan_out_test`, join fan-out; `orphan_test`,
referential integrity on the declared joins; `additivity_test`,
whether the value column says how it combines. Each reads the evidence
the quality kit stored and never the data again. The server runs them
after a call that defines a metric, glosses its columns or imports a
table it scans, and again the ones whose result predates a measurement
the call made, so the line reads results. `metric_tests()` lists every
test on each metric and on what it reads, a team's own tests included
([views and table functions](../reference/reads.md#metric_tests)).

The step is the worst state: red, then orange, yellow (a check whose
evidence is not stored yet, or a definition whose columns carry no
role), unassessed. A result that predates a change to what it read
keeps its band and says so; the server runs it again at the next touch.
The statement settles it: a fix to the definition or the load, the
measurement to run, or, where the number is right as it is, a tolerance
a person records on the metric.

## Reading it

```sql
SELECT surface, step, state, say, statement FROM next ORDER BY goal, surface
```

One row per goal: `state` is `next`, `blocked` or `done`; `say` is the
action in a clause; `why` is what in the catalog decided; `statement`
is the action as a statement, filled from the catalog, with `<…>` where
only the author can fill in; `then` is what follows it
([views and table functions](../reference/reads.md#next)).

Over MCP, every tool result ends with the same rows as one line:

```text
next: staff_by_title → the join in staff_by_title fans out on dept_emp.emp_no ~ titles.emp_no (next://hr/staff_by_title) · done: headcount, review
```

Each link is a resource, `next://<dataset>/<goal>`, which serves the
action, why, the statement and what follows, as markdown
([MCP interface](../reference/mcp.md)).

## How a goal is built

Each kit declares a table macro `routes_<kit>()` that returns two
columns of SQL text:

- `ctes`: common table expressions the kit's steps need, or `''`;
- `arms`: its steps, one `SELECT` per step, joined by `UNION ALL`.

Each step returns the columns `surface` (the goal), `step`, `state`,
`act`, `say`, `why`, `statement` and `"then"`, and returns a row only
when its condition holds. For each goal, the lowest step that returns a
row decides. The last step of a goal is an unconditional `done`.

At every open the server writes `next` from every `routes_<name>()`
macro in the lake's `main` schema. The steps read the catalog, never
the data, through relations the server computes once: `ds` (the bound
dataset), `axes` (`metric_axes()`), `open_items`, `reds` (red test
results) and `bodies` (the current metric definition per metric). The
metrics' goals sort first, `review` next, the outlook's after; a goal
the server does not know sorts with the metrics.

## Adding a goal

A kit adds a goal by declaring its own `routes_<kit>()`:

```sql
CREATE OR REPLACE MACRO main.routes_contracts() AS TABLE
SELECT '' AS ctes, $arms$
SELECT 'contracts' AS surface, 1 AS step, 'next' AS state, 'GLOSS contract' AS act,
       'write the contract for ' || t.table_name AS say,
       t.table_name || ' has no contract' AS why,
       'GLOSS contract ON ' || t.table_name || ' AS $${"owner": "<team>"}$$;' AS statement,
       '' AS "then"
FROM (SELECT DISTINCT table_name FROM glossql_columns(current_schema(), false)) t, ds
WHERE NOT EXISTS (SELECT 1 FROM main.glossary g
                  WHERE g.dataset = ds.dataset AND g.aspect = 'contract' AND g.subject = t.table_name)
UNION ALL
SELECT 'contracts', 2, 'done', '', '', 'every table has a contract', '', ''
FROM ds
$arms$ AS arms;
```

The goal joins `next` at the next open. Test its steps in the kit's
suite, as the shipped kits do.
