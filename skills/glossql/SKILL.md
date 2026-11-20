---
name: glossql
description: Build a company's data intelligence layer in a glossdb workspace over the MCP interface — connect sources, describe the data, keep every query worth keeping as a view (a plain view, a table, a single value, a metric, a rule), test it, and leave decisions to a person. The entry skill — what to keep as a view and when, the four kinds of work with a working example each, how to read `next`, the statements and the reads. Use for any work in a glossdb workspace.
---

# Building the data intelligence layer

glossdb is the data harness for people and agents. You build the
workspace's data intelligence layer in the lake, beside the data:
what the data means, how its sources map, whether it can be trusted,
and who decides. What you state is stored with the data and tested
against it after each load. A person reviews and decides.

| Kind of work | What you do |
|---|---|
| integrate | connect a source, load its tables, define views |
| describe | annotate what a table, a column, a relationship or a view means |
| test | check what was stated against the data |
| review | give a judgment call to a person, and apply their decision |

They are kinds of work, not stages. What the person asked for decides
what you do and when.

## What you keep: views

Everything you keep is a view: a named SQL query on the dataset, with
its reason. One statement defines it. Its kind says what it is for:

| Kind | What it is |
|---|---|
| none | a plain view: a query worth reading again, the evidence behind a decision. It asks for nothing more |
| `table`, `value`, `metric` | what the dataset serves. `next` asks for their descriptions, and the built-in tests run on them |
| `rule` | a query whose rows break a rule. It must return none. A test runs on it after every write; only a person accepts a count of rows |

```glossql
GLOSS status_spellings ON logistics AS $${"sql": "SELECT status, count(*) AS deliveries FROM deliveries GROUP BY status",
  "meaning": "the status values as the carrier writes them; DELIVERED and delivered are one status", "tags": ["status", "mapping"]}$$;
GLOSS weight_positive ON logistics AS $${"kind": "rule", "sql": "SELECT delivery_id, weight_kg FROM deliveries WHERE weight_kg <= 0",
  "meaning": "a delivery weighs more than nothing"}$$;
```

`meaning` and `tags` in the body are the view's `meaning` and `tags`
annotations. A view is read as `FROM <view>`, and a view can read
other views. Defining a name again replaces its definition.

When to write what:

| You have | Keep it as |
|---|---|
| a query whose answer decided something: a profile, a comparison of two sources, the values a mapping covers, a unit | a plain view, with `meaning` and `tags` |
| rows or numbers the dataset serves | a `table`, `value` or `metric` view |
| a condition the data must hold | a `rule` view: the rows that break it |
| a share of rows that may break a rule, with a tolerance | a test of your own, five statements (`skill://glossql-modeling/references/tests.md`) |
| one stored value per asset that many assets need | a function (`skill://glossql-functions/SKILL.md`); seldom needed |

Keep each query that decided a filter, a cast, a mapping or a unit,
and tag it. `find('<term>')` searches names, meanings, tags, kinds and
the columns each view reads, so the next agent and the reviewer find it:

```sql
SELECT asset, what, kind, meaning, tags, matched_on FROM find('status')
```

Tag a table or a column too. Your newest list of tags replaces your
list before; `SELECT tag_statement('<dataset>.<asset>', ['<word>'])`
gives the statement with the word added.

## The interface and `next`

One tool, `glossql`, takes statements separated by `;` and returns
one outcome per statement: rows for a read (a null field is left out
of its row; `truncated: true` means the row cap cut the result),
`done` for a write, an error that names what was wrong for a refused
statement. The statements before a refused one stay stored. On the
workspace endpoint (`/mcp`), begin a call that names a dataset's
tables or views with `USE <dataset>;`. On `/<dataset>/mcp` every call
opens on that dataset. Read the catalog as `main.<relation>`: a table
of the same name in a dataset would hide it.

Every result ends with `status:`, the outcome of the last statement.
A call on a dataset adds `next:` and `first:`:

```text
status: done
next: must test 1 · should describe 2 · waiting for a person 1
first: must test logistics.weight_positive (red): rule_test: 2 rows break the rule weight_positive … (next://logistics/test)
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
SELECT level, kind, asset, state, open, statement FROM main.next WHERE level <> 'could'
```

`kind` is the row's kind of work. Each row has a statement that opens
it; `<…>` marks what you fill in. A comment line (`--`) above a
statement says why the row is open, or which of two statements it is
and when to take it; a statement a person must decide is handed
commented out. Where data changed under the row, a comment names
`load_changes()`, the read of what the newest load changed. `level`
says how much the row matters:

- `must`: served data is wrong or cannot be served. A red test (a
  rule view that returns rows, a metric that serves no series), a
  conflict between two values, a decision a person made that the
  definition does not carry yet.
- `should`: the layer is incomplete for what is served. A missing or
  outdated annotation on what a view reads or serves, a test not run
  or yellow with a fix (a join with no declared relationship is one:
  `relationship_test`), a load that does not fit what the source sends,
  an assumption waiting for a person, a stored result out of date.
- `could`: what sits beside it, such as the tables no view reads. Read
  it on request: `SELECT kind, asset, open, statement FROM main.next
  WHERE level = 'could'`.

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
column (`table.column`), a relationship, a view or the dataset.

| Property | On | Value |
|---|---|---|
| `entity` | a table | `{"value": "<what one row is>", "role": "fact"` or `"dimension", "grain": ["<key column>"], "time_axis": "<date column>"}` |
| `meaning` | a table, a column, a relationship, a view | `{"value": "<one sentence>"}` |
| `tags` | any asset | `{"value": ["<word>"]}` |
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

`next` asks for the annotations on what your served views read, so
its `describe` rows appear once a table, value or metric view exists.
After a load changes a column, its annotations read `stale`; `next`
hands each back with its value to check and record again.

## Integrate: the views the dataset serves

**A table** (`"kind": "table"`): cleaned, joined or reshaped rows.

```glossql
GLOSS clean_deliveries ON logistics AS $${
  "kind": "table", "sql": "SELECT delivery_id, depot_id, delivered_on, parcels, weight_kg, lower(status) AS status FROM deliveries",
  "meaning": "one delivery run, its status in lower case",
  "assumptions": [{"dimension": "convention", "key": "status-lower-case", "assumption": "status is served in lower case; DELIVERED and delivered are one status", "basis": "the view status_spellings: 1 of 10 rows is upper case", "confidence": 0.8}]
}$$;
```

**A single value** (`"kind": "value"`): one row with a column `value`.

```glossql
GLOSS depots_in_service ON logistics AS $${"kind": "value", "sql": "SELECT count(*) AS value FROM depots", "meaning": "depots that send deliveries"}$$;
```

**A metric** (`"kind": "metric"`): a value per period, with
dimensions. Name the time column, the measure with its additivity,
and the dimension columns:

```glossql
GLOSS parcels_delivered ON logistics AS $${
  "kind": "metric", "sql": "SELECT d.delivered_on, d.parcels AS value, d.depot_id, p.city FROM clean_deliveries d JOIN depots p ON p.depot_id = d.depot_id WHERE d.status = 'delivered'",
  "meaning": "parcels handed over per day, depot and city",
  "time": "delivered_on",
  "measure": {"column": "value", "additivity": "additive", "unit": "parcels"},
  "dimensions": ["depot_id", "city"],
  "assumptions": [{"dimension": "scope", "key": "delivered-only", "assumption": "only deliveries with status delivered count; returned and lost are left out", "basis": "the status values", "confidence": 0.7}]
}$$;
```

A metric also needs a grain for its series. Where its dates follow no
regular grain, `next` gives the statement:

```glossql
GLOSS time_grains ON logistics.parcels_delivered.delivered_on AS $${"floor": "month"}$$;
```

On a table view `next` also asks for `entity`, and for `meaning` and
`role` on its columns. A table in a given target format (a data
contract), metric shapes, stopping a view:
`skill://glossql-modeling/references/define.md`.

## Test: check what you stated

The server runs the built-in tests on each table, value and metric
view after you define it or load a table it reads: join fan-out,
referential integrity on declared relationships, effective-dated
tables, completeness, and for a metric additivity and its series. A
test that is not green is a row of `next` with its finding and a fix.
Fix the load or the definition. Where the number is right as it is,
accept the rate with a reason; a person can overrule it:

```glossql
GLOSS orphan_check ON logistics.parcels_delivered AS $${"tolerance": 0.1, "basis": "depot 099 closed in 2025 and is not in the depot list"}$$;
```

A rule of your own is a `rule` view, as above. Its test runs after
every write, with no further statement. While the view returns rows
it is a `must` row of `next`, with the count, the first rows and two
statements: the read of the rows, and the annotation by which a person
accepts that count with the reason. Only a person writes it, in the
console or over the query endpoint:

```glossql
GLOSS rule_check ON logistics.weight_positive AS $${"accepted": 2, "basis": "two test runs the carrier sends with weight 0"}$$;
```

A rule allows a share of rows, such as 5% of deliveries late, only as
a test of your own with a tolerance: five statements, in
`skill://glossql-modeling/references/tests.md`.

## Review: leave judgment to a person

A judgment call is a choice the data cannot settle: which rows count,
which date, how a text column is written. State each as an assumption
in the view's definition, with a `key` you choose and a `confidence`
below 1, as in the examples above. Each is a question in the review
queue:

```sql
SELECT property, key, assumption, basis, conf FROM main.open_questions
```

A person confirms or corrects it in the console. Where the person is
in chat with you, ask there and tell them to record the answer in the
console. The decision is stored as the person's annotation. It then
appears in `next` as a `review` row, with the definition to record
again. Do not ask a person for something the data can tell you:
measure it, and keep the query as a view. More: `references/review.md`.

## The other statements

| Statement | Does |
|---|---|
| `IMPORT t;` | loads the table again from the source |
| `DROP TABLE t;` | removes a table; refused while it holds data or annotations |
| `DECLARE RELATIONSHIP a.(x, y) -> b.(x, y);` | a join on a composite key |
| `GLOSS v ON <dataset> AS $${"stopped": "<why>"}$$;` | stops a view: it serves nothing, and readers get the reason |
| `DECLARE PROPERTY p WITH $$json schema$$ AS FACT ON TABLE, COLUMN;` | adds a property that agents and people annotate; `AS MEASUREMENT` for one only a function fills, such as a profile |
| `DECLARE TEST t ON p BY (AGENT, HUMAN) DETECTOR f THRESHOLD x;` | a test; `BY` names who may annotate the property; `THRESHOLD` applies where no annotation carries a `tolerance` |

A body goes inside `$$…$$` as it is, with plain double quotes. `CREATE
VIEW` and other DDL are closed: tables come from load queries, views
from definitions. A named argument to a read is written `:=`. The
language is `doc://SPEC.md` and `doc://grammar.ebnf`; the engine is
DuckDB, and its SQL guide is `doc://vendor/duckdb/sql/…`.

## The reads

| Read | Gives |
|---|---|
| `main.next` | what is open on the dataset: `level` (`must`, `should`, `could`), `kind` (the kind of work), the statement that opens it |
| `find('<term>')` | the views, tables and columns a term names: `asset`, `what`, `kind`, `meaning`, `tags`, `matched_on`, `reads`, `sql` |
| `main.view_definitions` | every view: `name`, `kind` (`table`, `value`, `metric`, `rule`, NULL for a plain view), `unit`, `meaning`, `defined`, `stopped`, `sql` (the view's SQL) |
| `view_summary()` | one row per served view: `kind`, `stopped`, value column, `additivity`, `dims`, `missing`; for a metric also `applicable` and `reason` (whether a series is served), the period column, `floor` and `window_periods` |
| `view_tests()` | the tests on each view and on what it reads, worst first |
| `views_lineage(dataset)` | lineage: per view column the loaded columns it is computed from (`inputs`) |
| `fact_values()` | each single value: `view`, `value`, `reason` |
| `metric_series(grain := 'month')` | each metric per period, dimension and member; `dimension = ''` is the total. `view := '<metric>'` reads one metric alone. It serves the newest periods only, by default 48 months or 20 years: `window_periods` in `view_summary()` (`time-grains.md`) |
| `GLOSSARY(asset)` | the annotations in force: `subject, property, value, test_state, score, state`; `GLOSSARY(asset, all => true)` gives every author's value |
| `TESTS(asset)` | test results: `subject, property, test, state, score, computed_at, current, error` |
| `main.open_questions`, `main.review_decisions`, `main.agent_assumptions` | the review queue, a person's decisions, your assumptions |
| `main.datasets`, `main.sources`, `main.recipes`, `main.imports`, `main.relationships`, `main.properties`, `main.functions`, `main.tests`, `main.glossary`, `main.results` | the catalog tables |
| `pages()` | every page this server serves: `uri`, `title`, `body` |

`DESCRIBE <read>` gives the columns of any of them. The loaded schema
is `information_schema.columns`.

## More

| Page | When |
|---|---|
| `skill://glossql-modeling/SKILL.md` | which kind of view; the judgment in each kind of work; its references: `load.md`, `define.md`, `harmonise.md` (several systems of record onto one table), `tests.md`, `time-grains.md`, `interfaces.md` |
| `references/review.md` | assumptions, review decisions, conflicts |
| `skill://glossql-apps/SKILL.md` | a data app over the views |
| `skill://glossql-functions/SKILL.md` | a function: one stored value per asset |
