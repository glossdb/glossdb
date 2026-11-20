---
name: glossql-modeling
description: The judgment inside each kind of work on a glossdb dataset — which kind of view fits the request, what a table is, which joins hold, how a measure adds up, what the data can settle before a person is asked, and what to hand back. Use with the glossql skill for any substantive work in a workspace; its references cover loading, defining views, tests, time grains and the other interfaces.
---

# Modeling: the judgment in each kind of work

`skill://glossql/SKILL.md` shows the four kinds of work (integrate,
describe, test, review) and their statements. This page says how to
decide inside them. The references go deeper.

## Start from the request

Agree in chat what the dataset is for and what it should serve,
before you load. Then pick the kind of view per item:

| The person asks for | Define |
|---|---|
| a cleaned, joined or reshaped table; a table in a given format (a data contract); a harmonised list across source systems | a table (`"kind": "table"`) |
| one number with no date: a count, a balance today, a threshold | a single value (`"kind": "value"`) |
| a number over time, by region, product or team | a metric (`"kind": "metric"`) |
| a condition the data must hold: a key that is unique, a code that is in its code table, two totals that match | a rule (`"kind": "rule"`): the rows that break it |

The queries you run on the way decide the served views: the values a
mapping covers, the unit a column is in, which rows a filter drops.
Keep each one that decided something as a plain view (no `kind`),
with its `meaning` and `tags`, so the next agent and the reviewer find
it with `find('<term>')`.

Build shared logic once: a table view that cleans a source can feed
several metrics and single values, and a decision on it reaches all
of them. Load only what the request needs. Something the data cannot
serve is a finding: say what is missing, and stop the view
(`references/define.md`).

## Tables: say what one row is

Judge from the data, not from the name.

- **`entity`**: what one row is, in the business's words; `role` is
  `fact` (events, carrying numbers) or `dimension` (things other
  tables refer to).
- **`grain`**: the columns that identify one row. Check it: the row
  count must equal the count of distinct grain values. A table with
  no key has no grain; say so in `meaning`.
- **`time_axis`**: the column that records when the row's event
  happened. A due date or a hire date is an attribute, not the axis.

```sql
SELECT count(*) AS n, (SELECT count(*) FROM (SELECT DISTINCT delivery_id FROM deliveries)) AS keys FROM deliveries
```

## Columns: role first

- **`meaning`**: one sentence on what the column holds, specific to
  this business. `term` is the name a report would print.
- **`role`**: `key`, `measure`, `dimension`, `timestamp` or
  `attribute`, judged from this table alone. A column that identifies
  the row or refers to another table (a foreign key) is `key`; `key`
  needs no further annotation. The join itself is declared as a
  relationship. Mark a foreign key `dimension` only where the view
  slices by the id itself; it then needs a `dimension` rank.
- **`additivity`**, on a measure. `additive`: rows of one period add
  up (parcels, hours). `semi-additive`: a level at a point in time
  that must not be summed over periods (stock, headcount). `ratio`:
  re-divided from its halves. `non-additive`: does not combine (a
  distinct count, a median). Read the column's meaning and the
  table's grain. A name can mislead: a column called `total` may
  hold a movement per period. Give the `basis`.
- **`unit`**: the unit as text; `source_column` names the column that
  holds it when it sits beside the value.
- **`dimension`**: `primary`, `supporting` or `none`. An id with
  nearly one value per row, a constant, or a column most rows leave
  empty is `none`.

Where the meaning does not settle a property, do not guess. A missing
annotation shows in `next`; a wrong one does not.

## Relationships: check before you declare

`detect_relationships()` proposes joins and includes false ones.

- Join both ways and read the rows that find no partner. Orphans that
  are one business population (cancelled orders, records before a
  migration) confirm the join. Scattered misses argue against it.
- Two id columns of integers can overlap by coincidence. The names,
  the values and the business meaning must agree.
- A composite key is declared whole, `a.(x, y) -> b.(x, y)`. Its
  first part alone repeats rows.
- A column that points at different tables by a type column is not a
  relationship. Say so in its `meaning`.
- Check a join before you build on it: the row count before and
  after must be equal, or the join repeats rows.

After `DECLARE RELATIONSHIP`, annotate its `meaning`, with what the
orphans are. `relationship_coherence()` measures one declared
relationship's orphan rate, run over its pair path
(`SELECT relationship_coherence() FROM orders.customer_id ->
customers.customer_id`); the server runs it for the built-in tests. Its `temporal` list compares the date columns of the two
tables, up to three per side, over the joined rows: `precedes_rate`
is the share of rows whose date in the referring table
(`child_column`) lies before the date in the table referred to
(`parent_column`). An order dated before its customer signed up is a
defect or a wrong join; a booking dated before its event is as
expected. Read the two column names before you judge the rate. A
table with one row per key and period of validity (prices,
assignments) is effective-dated: mark it with `validity`
(`references/tests.md`).

## Measure before you ask

A person decides definitions, conventions and business meaning. The
data settles the rest. Run the function; do not ask.

| Question | Function |
|---|---|
| what a column holds: nulls, distinct values, range | `SELECT column_profile() FROM t.c` |
| outliers in a numeric column | `SELECT outlier_profile() FROM t.c` |
| a date column's grain, span and gaps | `SELECT temporal() FROM t.c` |
| which columns join, and how well | `SELECT detect_relationships() FROM <dataset>`, then `relationship_coherence()` per relationship |
| whether a column is computed from others (a = b × c) | `SELECT detect_derivations() FROM t` |
| hierarchies among a table's columns | `SELECT detect_hierarchies() FROM t` |
| a level or a movement, where an event table exists | `SELECT additivity_evidence() FROM t.c` |
| two views with the same definition | `SELECT detect_definition_collisions() FROM <dataset>` |

A function is called in the SELECT list with its asset in FROM.
`SELECT * FROM column_profile()` is refused. Its result is stored and
served again while the data is unchanged. Every function:

```sql
SELECT name, scope, returns FROM main.functions ORDER BY name
```

A query of your own that settles a question is a plain view, not a
function: keep it with the reason it decided something.

## The engine

The engine is DuckDB; look a function up in its SQL guide,
`doc://vendor/duckdb/sql/…`. `SET`, `ATTACH`, `INSTALL`, `LOAD`,
`CALL`, `CREATE VIEW` and other DDL are closed. Names are
case-insensitive; quote a reserved word (`"order"`). A column loaded
as text sorts as text (`'99' > '100'`) and does not sum: the cast
belongs in the load query. `CAST` fails the statement on a value that
does not convert; `try_cast` gives NULL.

## What you hand back

When `next` shows no `must` and no `should` for you, read back what you served and
compare it with a figure the person already trusts: a table view's
row count, a metric's total. Then report in three lists:

1. **Choices**: each assumption whose basis is your judgment, with
   its alternative. They are in the review queue.
2. **Findings**: a defect and its size, rows a load dropped, a test
   you accepted with a tolerance, a view you stopped.
3. **Missing material**: what only something from outside settles: a
   code table, a prior-year file, the policy that names a convention.

## References

| Page | When |
|---|---|
| `references/load.md` | sources, load queries, CSV files, dropped rows |
| `references/define.md` | the kinds of view; a table to a data contract; metric shapes; stopping a view |
| `references/harmonise.md` | several systems of record mapped onto one target table: the branches, the contract, the mapping, the reconciliation (preview) |
| `references/tests.md` | the built-in tests, rule views, a test with a tolerance |
| `references/time-grains.md` | reading a metric: grains, windows, dimensions |
| `references/interfaces.md` | the console, the query endpoint, exports |
| `skill://glossql/references/review.md` | assumptions, review decisions, conflicts |
