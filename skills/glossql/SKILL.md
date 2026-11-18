---
name: glossql
description: Build a company's data intelligence layer in a glossdb workspace over the MCP interface — connect sources, describe the data, define views (a table, a single value, a metric), test them, and leave decisions to a person. The entry skill — the four kinds of work (integrate, describe, test, review) with a working example each, how to read `next`, the statements and the reads. Use for any work in a glossdb workspace.
---

# Building the data intelligence layer

glossdb is the data harness for people and agents. You build the
workspace's data intelligence layer in the lake, beside the data:
what the data means, how its sources map, whether it can be trusted,
and who decides. Source data goes in. Described and tested tables,
single values and metrics come out, as views any tool that opens the
lake can read. What you state is stored with the data and tested
against it after each load. A person reviews and decides.

There are four kinds of work:

| Kind | What you do |
|---|---|
| integrate | connect a source, load its tables, define views |
| describe | annotate what a table, a column or a relationship means |
| test | check what was stated against the data |
| review | give a judgment call to a person, and apply their decision |

They are kinds of work, not stages. Three things are fixed: a view
needs a loaded table, a test needs something defined, and a review
needs an open question. Lineage needs no work of its own: each load
and each view definition records it. A view can be queried once it
is defined.

This page shows each kind once, on a dataset of parcel deliveries,
starting from an empty workspace. That order is one way through, not
the rule. What the person asked for decides what you do and when.

## The interface and `next`

One tool, `glossql`, takes statements separated by `;` and returns
one outcome per statement: rows for a read (a null field is left out
of its row; `truncated: true` means the row cap cut the result),
`done` for a write, an error that names what was wrong for a refused
statement. The statements before a refused one stay stored. On the
workspace endpoint (`/mcp`), begin a call that names a dataset's
tables or views with `USE <dataset>;`. On `/<dataset>/mcp` every call
opens on that dataset.

Every result ends with `status:`, the outcome of the last statement.
A call on a dataset adds `next:` and `first:`:

```text
status: done
next: must test 1 · should describe 2 · waiting for a person 1
first: must test logistics.parcels_delivered (red): orphan_test: 10.0% of rows … find no parent (next://logistics/test)
```

`next:` counts what must and what should be done on the dataset, per
kind of work, and the assumptions that wait for a person apart.
`first:` is the first row that must be done, else the first that
should. A call on the workspace endpoint without `USE` has neither. Two
more lines appear when they apply: `summary:` after a call that
changed what waits in the workspace (assumptions for a person,
decisions to apply), and `window:` after a read of `metric_series()`.
Read the list after a piece of work, in a call of its own:

```sql
SELECT level, kind, asset, state, open, statement FROM next WHERE level <> 'could'
```

`kind` is the row's kind of work. Each row has a statement that opens
it; `<…>` marks what you fill in. A comment line (`--`) above a
statement says why the row is open, or which of two statements it is
and when to take it; a statement a person must decide is handed
commented out. Where data changed under the row, a comment names the read
that says what the newest load changed, `load_changes()`. `level` says how much the row matters:

- `must`: served data is wrong or cannot be served. A red test (a
  metric that serves no series is one: `series_test`), a conflict
  between two values, a decision a person made that the definition
  does not carry yet.
- `should`: the layer is incomplete for what is served. A missing or
  outdated annotation on what a view reads or serves, a test not run
  or yellow with a fix (a join with no declared relationship is one:
  `relationship_test`), a load that does not fit what the source sends,
  an assumption waiting for a person, a stored result out of date.
- `could`: what sits beside it, such as the tables no view reads. Read
  it on request: `SELECT kind, asset, open, statement FROM next WHERE
  level = 'could'`.

The list is ordered by level, then by what blocks other work. The
work on a dataset is complete when no `must` row is open; the `should`
rows make the layer complete. Rows that wait for a person do not hold
you back. The list is context: what the person asked for decides what
you work on.

## Integrate: connect a source, load tables

```glossql
DECLARE DATASET logistics SET (purpose: 'parcel deliveries by depot');
DECLARE SOURCE carrier SET (type: csv, location: '/data/carrier');
PREVIEW carrier AS $$SELECT file FROM glob('*')$$;
```

A source is a directory, an object-store URL or a database. `PREVIEW`
runs SQL at the source and loads nothing; with `LIMIT 0` it returns
every column and type. A load query (`DECLARE RECIPE`) is the SQL that
produces a table, and declaring it loads the table. A typed source
loads as it is:

```glossql
DECLARE RECIPE depots ON logistics FROM carrier AS $$
  SELECT depot_id, city, opened FROM read_parquet('depots.parquet')$$;
```

A CSV has no types. Read it with these options and write the casts
in the SELECT, each over `trim(…)`:

```glossql
DECLARE RECIPE deliveries ON logistics FROM carrier SET (key: delivery_id) AS $$
  SELECT delivery_id, trim(depot_id) AS depot_id,
         try_cast(trim(delivered_on) AS DATE) AS delivered_on,
         try_cast(trim(parcels) AS INTEGER) AS parcels,
         try_cast(trim(weight_kg) AS DOUBLE) AS weight_kg, status
  FROM read_csv('deliveries.csv', all_varchar = true,
                nullstr = null_markers(), store_rejects = true)$$;
```

The acknowledgement counts: `loaded logistics.deliveries: 10 rows, 0
dropped`. Look into every dropped row. `IMPORT deliveries;` loads the
table again. More: `skill://glossql-modeling/references/load.md`.

## Describe: annotate what the data means

An annotation (`GLOSS`) writes one property of one asset: a table, a
column (`table.column`), a relationship or the dataset.

| Property | On | Value |
|---|---|---|
| `entity` | a table | `{"value": "<what one row is>", "role": "fact"` or `"dimension", "grain": ["<key column>"], "time_axis": "<date column>"}` |
| `meaning` | a table, a column, a relationship | `{"value": "<one sentence>"}` |
| `role` | a column | `key` (an identifier or a foreign key), `measure`, `dimension`, `timestamp` or `attribute` |
| `additivity`, `unit` | a column with role `measure` | `additive`, `semi-additive`, `ratio` or `non-additive`; the unit as text |
| `dimension` | a column with role `dimension` | `primary`, `supporting` or `none` |
| `time_grains` | a column with role `timestamp` | `{"floor": "day"}`, the finest grain it is read at |

```glossql
GLOSS entity ON deliveries AS $${"value": "one delivery run from a depot", "role": "fact",
  "grain": ["delivery_id"], "time_axis": "delivered_on"}$$;
GLOSS meaning ON deliveries.parcels AS $${"value": "parcels handed over on the delivery"}$$;
GLOSS role ON deliveries.parcels AS $${"value": "measure"}$$;
GLOSS additivity ON deliveries.parcels AS $${"value": "additive"}$$;
GLOSS unit ON deliveries.parcels AS $${"value": "parcels"}$$;
```

Annotate `role` first: it decides which other properties a column
needs. A foreign key column is `key`, and `key` needs nothing more.
Look before you write: `SELECT column_profile() FROM
deliveries.parcels`. A join between two tables is a relationship;
check a proposed one against the data before you declare it:

```glossql
SELECT detect_relationships() FROM logistics;
DECLARE RELATIONSHIP deliveries.depot_id -> depots.depot_id;
GLOSS meaning ON deliveries.depot_id -> depots.depot_id AS $${"value": "each delivery leaves from one depot"}$$;
```

`next` asks for the annotations on what your views read, so its
`describe` rows appear once a view exists. After a load changes a
column, its annotations read `stale`; `next` hands each back with its
value to check and record again.

## Integrate: define views

A view is named SQL on the dataset: declare the name, then define it.
There are three kinds, each read as `FROM <view>`.

**A table** (`x-kind: relation`): cleaned, joined or reshaped rows.

```glossql
DECLARE ASPECT clean_deliveries WITH $${"title": "Deliveries, cleaned", "x-kind": "relation"}$$ AS VIEW;
GLOSS clean_deliveries ON logistics AS $${
  "sql": "SELECT delivery_id, depot_id, delivered_on, parcels, weight_kg, lower(status) AS status FROM deliveries",
  "assumptions": [{"dimension": "convention", "key": "status-lower-case", "assumption": "status is served in lower case; DELIVERED and delivered are one status", "basis": "1 of 10 rows is upper case", "confidence": 0.8}]
}$$;
```

**A single value** (`x-kind: scalar`): one row with a column `value`.

```glossql
DECLARE ASPECT depots_in_service WITH $${"title": "Depots in service", "x-kind": "scalar"}$$ AS VIEW;
GLOSS depots_in_service ON logistics AS $${"sql": "SELECT count(*) AS value FROM depots"}$$;
```

**A metric**: a value per period, with dimensions. Name the time
column, the measure with its additivity, and the dimension columns:

```glossql
DECLARE ASPECT parcels_delivered WITH $${"title": "Parcels delivered"}$$ AS VIEW;
GLOSS parcels_delivered ON logistics AS $${
  "sql": "SELECT d.delivered_on, d.parcels AS value, d.depot_id, p.city FROM clean_deliveries d JOIN depots p ON p.depot_id = d.depot_id WHERE d.status = 'delivered'",
  "time": "delivered_on",
  "measure": {"column": "value", "additivity": "additive", "unit": "parcels"},
  "dimensions": ["depot_id", "city"],
  "assumptions": [{"dimension": "scope", "key": "delivered-only", "assumption": "only deliveries with status delivered count; returned and lost are left out", "basis": "the status values", "confidence": 0.7}]
}$$;
```

A table and a single value can be queried once they are defined. A
metric also needs a grain for its series. Where its dates follow no regular
grain, `next` gives the statement:

```glossql
GLOSS time_grains ON logistics.parcels_delivered.delivered_on AS $${"floor": "month"}$$;
```

`next` then asks for `meaning` on each view. On a table view it also
asks for `entity`, and for `meaning` and `role` on its columns. A
view's `meaning` is what `view_definitions` shows. A table in a
given target format (a data contract), metric shapes, stopping a
view: `skill://glossql-modeling/references/define.md`.

## Test: check what you stated

The server runs the built-in tests on each metric after you define
it or load a table it reads: join fan-out, referential integrity on
declared relationships, effective-dated tables, additivity. A test
that is not green is a row of `next` with its finding and a fix. Fix
the load or the definition. Where the number is right as it is,
accept the rate with a reason; a person can overrule it:

```glossql
GLOSS orphan_check ON logistics.parcels_delivered AS $${"tolerance": 0.1, "basis": "depot 099 closed in 2025 and is not in the depot list"}$$;
```

A test of your own has four parts: a property for the expectation, a
function that measures how often the data breaks it, the test, and
the expectation annotated on the asset it holds for.

```glossql
DECLARE ASPECT delivery_key_unique WITH $${"type": "object",
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"}, "basis": {"type": "string"},
                 "breach_rate": {"type": "number"}, "finding": {"type": ["string", "null"]}}}$$ AS FACT ON TABLE;
DECLARE FUNCTION delivery_key_check FOR logistics AS $$
  SELECT (count(*) - count(DISTINCT delivery_id)) / greatest(count(*), 1)::DOUBLE AS breach_rate,
         CASE WHEN count(*) > count(DISTINCT delivery_id)
              THEN (count(*) - count(DISTINCT delivery_id)) || ' rows repeat a delivery_id' END AS finding
  FROM clean_deliveries
$$ RETURNS delivery_key_unique;
DECLARE TEST delivery_key_test ON delivery_key_unique BY (AGENT, HUMAN) DETECTOR rate_tolerance;
GLOSS delivery_key_unique ON clean_deliveries AS $${"outcome": "a delivery_id names one delivery run",
  "tolerance": 0.0, "basis": "the carrier issues one id per run"}$$;
SELECT delivery_key_check() FROM clean_deliveries;
```

- **The property** is declared `AS FACT`. Its annotation is the
  expectation: `outcome` says the rule in words, `tolerance` is the
  share of rows that may break it (0.0 allows none), `basis` says
  why.
- **The function** returns `breach_rate`, the share of rows that
  break the rule, and `finding`, one sentence on what is wrong. Its
  `RETURNS` names the property.
- **The test** scores one against the other: green at or under the
  tolerance, red above it, yellow while the function has not run.
- **The annotation** sets the test on that asset. The test is on no
  other asset, and `next` asks for it nowhere else.

Run the function once. After a later load the server runs it again.
A test on one column is declared `ON COLUMN`, and annotated and run
on the column:

```glossql
DECLARE ASPECT weight_filled WITH $${"type": "object",
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"}, "basis": {"type": "string"},
                 "breach_rate": {"type": "number"}, "finding": {"type": ["string", "null"]}}}$$ AS FACT ON COLUMN;
DECLARE FUNCTION weight_filled_check FOR logistics AS $$
  SELECT count(*) FILTER (WHERE weight_kg IS NULL) / greatest(count(*), 1)::DOUBLE AS breach_rate,
         CASE WHEN count(*) FILTER (WHERE weight_kg IS NULL) > 0
              THEN count(*) FILTER (WHERE weight_kg IS NULL) || ' deliveries have no weight' END AS finding
  FROM deliveries
$$ RETURNS weight_filled;
DECLARE TEST weight_filled_test ON weight_filled BY (AGENT, HUMAN) DETECTOR rate_tolerance;
GLOSS weight_filled ON deliveries.weight_kg AS $${"outcome": "each delivery has a weight",
  "tolerance": 0.0, "basis": "the carrier bills by weight"}$$;
SELECT weight_filled_check() FROM deliveries.weight_kg;
```

A test states the rule. Where the data breaks it, the test is red and
a row of `next`, with the finding and two statements: the check to
run again after you fixed the load query or the definition, and the
annotation that records a rate a person accepts. That annotation is
the same property on the same asset, with a higher `tolerance` and
the person's reason in `basis`. A person's annotation outranks yours.
More: `skill://glossql-modeling/references/tests.md`.

## Review: leave judgment to a person

A judgment call is a choice the data cannot settle: which rows count,
which date, how a text column is written. State each as an assumption
in the view's definition, with a `key` you choose and a `confidence`
below 1, as in the examples above. Each is a question in the review
queue:

```sql
SELECT aspect, key, assumption, basis, conf FROM open_questions
```

A person confirms or corrects it in the console. Where the person is
in chat with you, ask there and tell them to record the answer in the
console. The decision is stored as the person's annotation. It then
appears in `next` as a `review` row, with the definition to record
again. Do not ask a person for something the
data can tell you: measure it. More: `references/review.md`.

## The other statements

| Statement | Does |
|---|---|
| `IMPORT t;` | loads the table again from the source |
| `DROP TABLE t;` | removes a table; refused while it holds data or annotations |
| `DECLARE RELATIONSHIP a.(x, y) -> b.(x, y);` | a join on a composite key |
| `DECLARE ASPECT p WITH $$json schema$$ AS FACT ON TABLE, COLUMN;` | adds a property that agents and people annotate; `AS MEASUREMENT` for one only a function fills, such as a profile |
| `DECLARE TEST t ON p BY (AGENT, HUMAN) DETECTOR f THRESHOLD x;` | a test; `BY` names who may annotate the property; `THRESHOLD` applies where no annotation carries a `tolerance` |

A body goes inside `$$…$$` as it is, with plain double quotes. `CREATE
VIEW` and other DDL are closed: tables come from load queries, views
from definitions. A named argument to a read is written `:=`. The
language is `doc://SPEC.md` and `doc://grammar.ebnf`; the engine is
DuckDB, and its SQL guide is `doc://vendor/duckdb/sql/…`.

## The reads

| Read | Gives |
|---|---|
| `next` | what is open on the dataset: `level` (`must`, `should`, `could`), `kind` (the kind of work), the statement that opens it |
| `view_summary()` | one row per view: `kind`, `stopped`, value column, `additivity`, `dims`, `missing`; for a metric also `applicable` and `reason` (whether a series is served), the period column, `floor` and `window_periods` |
| `view_definitions` | every view: `name`, `title`, `kind` (`relation`, `scalar`, `measure` for a metric), `unit`, `meaning`, `defined`, `stopped` |
| `view_tests()` | the tests on each view and on what it reads, worst first |
| `column_mapping()` | lineage: per view column and branch of a union the source system, `table.column` and expression |
| `fact_values()` | each single value: `view`, `value`, `reason` |
| `metric_series(grain := 'month')` | each metric per period, dimension and member; `dimension = ''` is the total. `view := '<metric>'` reads one metric alone. It serves the newest periods only, by default 48 months or 20 years: `window_periods` in `view_summary()` (`time-grains.md`) |
| `GLOSSARY(asset)` | the annotations in force: `subject, aspect, value, test_state, score, state`; `GLOSSARY(asset, all => true)` gives every author's value |
| `TESTS(asset)` | test results: `subject, aspect, test, state, score, computed_at, current, error` |
| `open_questions`, `review_decisions`, `agent_assumptions` | the review queue, a person's decisions, your assumptions |
| `datasets`, `sources`, `recipes`, `imports`, `relationships`, `aspects`, `functions`, `tests`, `glossary`, `measurements` | the catalog tables |
| `pages()` | every page this server serves: `uri`, `title`, `body` |

`DESCRIBE <read>` gives the columns of any of them. The loaded schema
is `information_schema.columns`.

## More

| Page | When |
|---|---|
| `skill://glossql-modeling/SKILL.md` | which kind of view; the judgment in each kind of work; its references: `load.md`, `define.md`, `harmonise.md` (several systems of record onto one table), `tests.md`, `time-grains.md`, `interfaces.md` |
| `references/review.md` | assumptions, review decisions, conflicts |
| `skill://glossql-apps/SKILL.md` | a data app over the views |
| `skill://glossql-functions/SKILL.md` | a function of your own |
