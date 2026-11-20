---
name: glossql-functions
description: Write a function for a glossdb workspace — a kit's machinery that stores one value per asset and computes it again when what it read changed (RETURNS a property, one SQL query over the data), or a detector (no RETURNS, one SQL query over the values a test collects). Use when a measure per asset is needed on many assets, when a test with a tolerance needs its check, or when a function answers that it does not apply. A query worth keeping is a view, not a function.
---

# Functions

A function is a kit's machinery. It stores one value per asset it
runs on, and the server computes the value again when what it read
changed. A query you want to read again is a view, not a function
(`skill://glossql/SKILL.md`). Write a function where:

- a measure per asset is needed on many assets: one function runs on
  each column of a table, or on each table of a dataset;
- a test with a tolerance needs its check
  (`skill://glossql-modeling/references/tests.md`, five statements);
- a test needs a detector of its own.

A function is declared with a statement and run by the server. Its
body is one read-only SQL query. There are two kinds:

- **A function with `RETURNS`** fills a property. Its query runs over
  the data; its result is validated against the property's JSON
  Schema and stored in `results`.
- **A detector** has no `RETURNS`. A test names it in its `DETECTOR`
  clause. Its query runs over `annotations`, the values the test
  collects, and returns a state per asset.

## Read a shipped one first

The shipped functions are rows, and the body is a column:

```sql
SELECT name, scope, returns FROM main.functions ORDER BY name
```

```sql
SELECT script FROM main.functions WHERE name = 'rate_tolerance'
```

`column_profile` is the shape of a function over one column;
`outlier_profile` builds on another function's result;
`rate_tolerance` is the detector most tests use.

## A function per asset

```glossql
DECLARE PROPERTY padded_text WITH $${"type": "object", "required": ["applicable"],
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "padded_share": {"type": ["number", "null"]}}}$$ AS MEASUREMENT ON COLUMN;
DECLARE FUNCTION padded_text FOR GLOBAL AS $$
  SELECT typeof(any_value(v)) = 'VARCHAR' AS applicable,
         CASE WHEN typeof(any_value(v)) <> 'VARCHAR' THEN 'not a text column' END AS reason,
         CASE WHEN typeof(any_value(v)) = 'VARCHAR'
              THEN count(*) FILTER (WHERE v::VARCHAR <> trim(v::VARCHAR)) / greatest(count(v), 1)::DOUBLE END AS padded_share
  FROM subject_column($subject)
$$ RETURNS padded_text;
```

- A property only a function fills is declared `AS MEASUREMENT`. The
  property of a test with a tolerance is declared `AS FACT`, since a
  person states the expectation on it (`tests.md`).
- `FOR` is a dataset or `GLOBAL`.
- `RETURNS` names the property the result fills. The property's `ON`
  says which kind of asset the function runs on: `ON COLUMN`, `ON
  TABLE`, `ON DATASET`.
- The body can read what a call can: tables, views by name, the
  catalog tables, other functions' stored results in `results`.
- `$subject` is the asset the function was run on, as a string.
  `subject_column($subject)` is that column as a relation with one
  column `v`, for a function that runs on any column.
- The result is stored by shape: one row and one column is the
  value; one row is an object of its columns; several rows are an
  array of objects. A null field is left out. Keep it small: a result
  that is a table belongs in a view.
- The body cannot contain `$$`.
- The name is the key in the workspace. Declaring a name again
  replaces the function, and its next run computes anew. One property
  is returned by one function; a second function for the same
  `MEASUREMENT` property is refused. Do not take a shipped name unless
  you mean to replace it.

Run it in the SELECT list, with the asset in FROM. A function on
columns, run on a table, computes each of its columns:

```glossql
SELECT padded_text() FROM deliveries;
```

A run stores a row in `results` with the versions of the data it
read. The same call returns the stored result while those are
unchanged (`computed` is false) and computes again when they moved. A
result with a `summary` object returns the summary; the full result
is `GLOSSARY(asset::property)`.

## Say when it does not apply

Where the asset does not fit, return a fact, not an error:
`applicable: false` and a `reason`, as above. A text column has no
outliers; the reason can say that a date loaded as text needs a cast
in the load query. Keep `applicable` in the property's `required`
list.

## A detector

A detector's query reads `annotations`: one row per author's value
for the test's property, `(subject, property, kind, test, actor,
actor_kind, current, written_at, body)`. `actor_kind` is `human`,
`agent` or `function`. `current` is false for a function's value
stored before the last change. `body` is a struct where every value
is a JSON object: read a field as `body['tolerance']`. A field no
value carries is an error at planning that names it.

The test's `THRESHOLD` is `$threshold`, NULL where the test has none.
Return one row per asset: `subject`, `state` (`green`, `yellow`,
`orange`, `red`) and `score` (0 to 1). No row means no result, not
green: keep a row for every `subject`.

`rate_tolerance` reads `breach_rate` from the function's value and
`tolerance` from a person's annotation, else an agent's, else the
test's threshold: green at or under it, red above, yellow while
nothing was computed. A test with a tolerance in full:
`skill://glossql-modeling/references/tests.md`.
