# Next steps

After every call, the agent is told where each goal stands and the one
action that moves it. This is the `next` view, built from the kits.
Kits add goals the same way.

## The goals

| Goal | Done when | From |
|---|---|---|
| `structure` | tables loaded, relationships declared and checked | `goals` kit |
| `metrics` | every metric the dataset claims is served or stopped | `metrics` kit |
| `slices` | every applicable metric slices by its dimension columns | `metrics` kit |
| `bands` | the expected-range walk exists and no band is red, or the red carries a question or a review decision (preview) | `outlook` kit |
| `checks` | the dataset's own tests exist, every test ran, none is red | `goals` kit |
| `app` | an app exists over the metrics | `goals` kit |
| `plan` | every plan is served and compared, none lies outside the forecast's band, or the gap carries a question or a review decision (preview) | `outlook` kit |
| `review` | nothing waits: review decisions applied, approved load queries declared again, contested values read | `goals` kit |

The goal is the caller's: what the person asked for decides which one
the agent follows. Nothing is stored about it, and no step is an order.

## Reading it

```sql
SELECT surface, step, state, say, statement FROM next ORDER BY goal
```

One row per goal: `state` is `next`, `blocked` or `done`; `say` is the
action in a clause; `why` is what in the catalog decided; `statement`
is the action as a statement, filled from the catalog, with `<…>` where
only the author can fill in; `then` is what follows it
([views and table functions](../reference/reads.md#next)).

Over MCP, every tool result ends with the same rows as one line:

```
next: structure: done · metrics → define churn (next://ops/metrics) · slices → blocked: no applicable metric exists · …
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
dataset), `axes` (`metric_axes()`), `open_items`, `reds` (red test results),
`bodies` (the current metric definition per metric) and `applicable`
(the applicable metrics). Goals sort in the order of the table above;
a goal the server does not know sorts last.

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
