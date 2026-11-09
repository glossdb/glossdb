# Statements

glossql adds a few statements and two table functions to DuckDB SQL.
Everything else is DuckDB's own SQL. This page lists each statement
with its form and an example. The normative text is
[SPEC.md](https://github.com/glossdb/glossql/blob/main/SPEC.md); the
syntax is `grammar.ebnf` in the same repository. Both are served on
the MCP interface as `doc://SPEC.md` and `doc://grammar.ebnf`.

Common rules:

- Every JSON or SQL body is dollar-quoted (`$$ … $$`, or `$tag$ … $tag$`
  when the body contains `$$`). The body is stored byte for byte.
- No statement names its author. The actor comes with the connection,
  and the server stores it with every write
  ([authentication](../operations/authentication.md)).
- A statement's identity is its content. Declaring the same thing again
  unchanged does nothing; a changed load query replaces its table.

## DECLARE SOURCE

```
DECLARE SOURCE <name> SET (type: <type>, location: '<path or URL>' [, via: <secret>])
```

Names where data comes from: a directory or URL prefix of `parquet`,
`csv` or `json` files, or a database the server has attached. The
location carries no credentials; `via` names a secret the engine holds.

```glossql
DECLARE SOURCE erp_export SET (type: parquet, location: 'lake/erp');
```

## PREVIEW

```
PREVIEW <source> AS $$<sql>$$
```

Runs a query at the source and loads nothing: a dry run of a load
query. The result always carries its schema, so `LIMIT 0` shows the
columns and types a load query would produce.

```glossql
PREVIEW erp_export AS $$SELECT file FROM glob('*')$$;
```

## DECLARE RECIPE

```
DECLARE RECIPE <table> ON <dataset> FROM <source> [SET (key: <column>[, …])] AS $$<sql>$$
```

A load query: the SQL that loads one table from a source. It runs at
the source, carries the casts, and its result is the typed table.
`SET (key: …)` names the table's key; a keyed table merges new rows by
that key on every load, an unkeyed one is replaced. A changed load
query replaces the table and keeps its annotations.

```glossql
DECLARE RECIPE sites ON ops FROM erp_export AS $$
  SELECT id, region, service_line FROM read_parquet('sites/*.parquet')$$;
```

## IMPORT

```
IMPORT [<dataset>.]<table>
```

Runs a table's load query again and makes the table its result as the
source is now, in one commit. Every load is a DuckLake snapshot with
its row count and column lineage
([loading data](../usage/loading-data.md)).

```glossql
IMPORT ops.sites;
```

## DECLARE DATASET and USE

```
DECLARE DATASET <name> SET (purpose: '<text>'[, …])
USE <dataset>
```

A dataset is a schema of the workspace's lake: the tables loaded for
one topic and the views over them. `USE` is DuckDB's own; unprefixed
`table` and `table.column` names resolve in the dataset in use
([workspaces and datasets](../usage/workspaces.md)).

```glossql
DECLARE DATASET fin SET (purpose: 'working-capital analysis over ERP and CRM exports');
USE fin;
```

## DECLARE RELATIONSHIP

```
DECLARE RELATIONSHIP [<dataset>.]<table>.<key> -> [<dataset>.]<table>.<key>
DECLARE RELATIONSHIP [<dataset>.]<table>.<key> <-> [<dataset>.]<table>.<key>
```

A declared join: `->` is many-to-one, `<->` one-to-one. A composite
key is a tuple, `orders.(region, order_no)`. Only declared
relationships exist; a candidate you reject is simply not declared
([relationships](../usage/relationships.md)).

```glossql
DECLARE RELATIONSHIP work_orders.site_id -> sites.id;
```

## DECLARE ASPECT

```
DECLARE ASPECT <name> WITH $${<JSON Schema>}$$ AS FACT [ON <grain>[, …] [WHEN <aspect> = '<value>']]
DECLARE ASPECT <name> WITH $${<JSON Schema>}$$ AS MEASUREMENT [ON <grain>[, …]]
DECLARE ASPECT <name> WITH $${<JSON Schema>}$$ AS VIEW
```

A property of the harness schema. `FACT` is a value an actor states,
`MEASUREMENT` a value a function computes, `VIEW` SQL served as a
view under the aspect's name. The grains are `DATASET`, `TABLE`,
`COLUMN`, `RELATIONSHIP` and `SOURCE`; none means all. `WHEN` makes the
aspect required only where a sibling aspect has that value; `WHEN TYPE
= '<type>'` where the column has that type
([describing data](../usage/describing-data.md)).

```glossql
DECLARE ASPECT currency WITH $${"type": "object", "required": ["value"],
  "properties": {"value": {"type": "string", "pattern": "^[A-Z]{3}$"}}}$$
  AS FACT ON COLUMN WHEN role = 'measure';
```

## GLOSS

```
GLOSS <aspect> ON <asset> AS $${<JSON>}$$
```

An annotation: one actor's value for one aspect on one asset. The body
is validated against the aspect's schema and stored with its actor and
the data snapshot it describes. The asset is a dataset, table, column,
relationship (`a.x -> b.y`) or source. On a `VIEW` aspect the body is
a metric definition, and the result is the metric's summary row
([metrics](../usage/metrics.md)).

```glossql
GLOSS unit ON orders.amount AS $${"value": "EUR", "source_column": "currency_code"}$$;
```

## DECLARE FUNCTION

```
DECLARE FUNCTION <name> FOR <dataset | GLOBAL> AS $$<sql>$$ [RETURNS <aspect>]
```

One SQL query. With `RETURNS` it is a measurement that fills that
aspect; without, a detector that scores a test. The body is stored with
the declaration, so `SELECT name, script FROM functions` reads the
whole library ([measurements](../usage/measurements.md),
[functions](functions.md)).

```glossql
DECLARE FUNCTION min_max FOR GLOBAL AS
  $$ SELECT min(v) AS min, max(v) AS max FROM subject_column($subject) $$ RETURNS min_max;
```

## DECLARE TEST

```
DECLARE TEST <name> ON <aspect> [BY (AGENT[, HUMAN])] [DETECTOR <function>] [THRESHOLD <0..1>]
```

A test on one aspect. `BY` lists the kinds of actor that may annotate
it; `DETECTOR` names the function that scores how far the values
agree; `THRESHOLD` is the score above which differing values read as
`conflict`. Name `BY`, `DETECTOR`, or both; a `MEASUREMENT` aspect
takes only a detector ([data tests](../usage/data-tests.md)).

```glossql
DECLARE TEST currency_test ON currency BY (AGENT, HUMAN) DETECTOR slot_entropy THRESHOLD 0.7;
```

## Running a measurement

```
SELECT <function>()[, …] FROM <asset>
```

Runs measurements on an asset. Each result is stored with the versions
of what it read and served again while those are unchanged. One row
per call: `function`, `subject`, `body`, `computed_at`, `computed`
(false when the stored row was served).

```glossql
SELECT column_profile(), outlier_profile() FROM orders.amount;
```

## DELETE FROM glossary

```
DELETE FROM [<lake>.][glossql.]glossary [WHERE <condition>]
```

Removes annotations. Open to every actor. The glossary spans every
dataset, so name the dataset in the `WHERE` to stay in one. A deleted
annotation stops serving and the one under it serves again. A metric's
view stays until a new definition or a stop replaces it, so retiring a
metric is a stop.

```glossql
DELETE FROM glossary WHERE dataset = 'fin' AND subject = 'orders.amount' AND aspect = 'unit';
```

## GLOSSARY()

```
GLOSSARY([<asset>[::<aspect>]][, all => true])
```

What is known: one row per asset and aspect, `(subject, aspect, value,
band, score, state)`. The value is a person's over an agent's over a
function's. `state` is `current`, `stale` (the data changed after the
annotation), `conflict` (actors disagree past the test's threshold)
or `missing` (required, and nobody annotated it). A missing value is
a visible row, never an omitted one. `all => true` returns every value
side by side. No argument covers the dataset in use; `::aspect`
narrows to one aspect.

```sql
SELECT * FROM GLOSSARY(orders.amount);
```

## TESTS()

```
TESTS([<asset>[::<aspect>]])
```

The test results: one row per asset, aspect and test, `(subject,
aspect, test, band, score, computed_at, current, error)`. `band` is
`green`, `yellow`, `orange`, `red` or `error`. Tests run when read.

```sql
SELECT subject, band FROM TESTS(fin.trial_balance) WHERE band = 'red';
```

## Metrics as relations

A metric's definition is a view in the dataset under the metric's
name. Read it like a table, bare under `USE` or as `dataset.metric`.
A metric and a loaded table of one dataset never share a name. The
series reads are in [views and table functions](reads.md).

## What the server refuses

Every actor can load tables, write rows, copy files in and out, drop
what it made, declare and annotate, and read: `DESCRIBE` any name a
read can plan, `SHOW TABLES` for the dataset in use. The engine's own
settings are closed: `SET`, `RESET`, `PRAGMA` switches, `ATTACH`,
`DETACH`, `INSTALL`, `LOAD`, `CALL`, `IMPORT DATABASE`, `EXPORT
DATABASE`. The refusal names the setting. A `PRAGMA` call with
parentheses is a read. Actors named in `GLOSSDB_ROOT` may use them
([configuration](../operations/configuration.md)).
