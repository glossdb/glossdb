---
name: glossql-functions
description: Write a function for a glossdb workspace — a measurement (RETURNS a property, one SQL query over the data) or a detector (no RETURNS, one SQL query over the values a test collects). Use when a shipped measurement does not fit the data, when a test of your own needs its check, or when a function answers that it does not apply.
---

# Functions

A function is declared with a statement and run by the server. Its
body is one read-only SQL query. There are two kinds:

- **A measurement** `RETURNS` a property. Its query runs over the
  data, and its result is validated against the property's JSON
  Schema and stored. The check behind a test is a measurement.
- **A detector** has no `RETURNS`. A test names it in its `DETECTOR`
  clause. Its query runs over `annotations`, the values the test
  collects, and returns a state per asset.

## Read a shipped one first

The shipped functions are rows, and the body is a column:

```sql
SELECT name, scope, returns FROM functions ORDER BY name
```

```sql
SELECT script FROM functions WHERE name = 'rate_tolerance'
```

`column_profile` is the shape of a measurement over one column;
`outlier_profile` builds on another function's aggregate;
`rate_tolerance` is the detector most tests use.

## A measurement

```glossql
DECLARE ASPECT late_deliveries WITH $${"type": "object",
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"}, "basis": {"type": "string"},
                 "breach_rate": {"type": "number"}, "finding": {"type": ["string", "null"]}}}$$ AS FACT ON TABLE;
DECLARE FUNCTION late_delivery_check FOR logistics AS $$
  SELECT CASE WHEN count(*) = 0 THEN 0.0
              ELSE count(*) FILTER (WHERE delivered_on > promised_on) / count(*)::DOUBLE END AS breach_rate,
         CASE WHEN count(*) FILTER (WHERE delivered_on > promised_on) > 0
              THEN count(*) FILTER (WHERE delivered_on > promised_on) || ' deliveries arrived after the promised day' END AS finding
  FROM deliveries
$$ RETURNS late_deliveries;
```

- The property here is the expectation of a test of your own, so it
  is declared `AS FACT` and also holds what a person states
  (`outcome`, `tolerance`, `basis`). A property only a function
  fills, such as a profile, is declared `AS MEASUREMENT`.
- `FOR` is a dataset or `GLOBAL`.
- `RETURNS` names the property the result fills. The property's `ON`
  says which kind of asset the function runs on: `ON COLUMN`, `ON
  TABLE`, `ON DATASET`.
- The body can read what a call can: tables, views by name, the
  catalog tables, other functions' stored results in `measurements`.
- `$subject` is the asset the function was run on, as a string.
  `subject_column($subject)` is that column as a relation named `v`,
  for a function that runs on any column.
- The result is stored by shape: one row and one column is the
  value; one row is an object of its columns; several rows are an
  array of objects. A null field is left out. Keep it small: a result
  that is a table belongs in a view.
- A result that read the catalog is computed again after any write to
  the catalog table it read. `DEPENDS ON $$query$$` after `RETURNS`
  narrows that: the query returns one value, such as a digest of the
  annotations the result uses, and the stored result is current while
  the query returns the same value and the tables and views the body
  read are unchanged.
- The body cannot contain `$$`.
- The name is the key in the workspace. Declaring a name again
  replaces the function, and its next run computes anew. One property
  is returned by one function; a second function for the same
  measurement property is refused. Do not take a shipped name unless
  you mean to replace it.

Run it in the SELECT list, with the asset in FROM:

```glossql
SELECT late_delivery_check() FROM deliveries;
```

A run stores a row in `measurements` with the versions of the data it
read. The same call returns the stored result while those are
unchanged (`computed` is false) and computes again when they moved. A
result with a `summary` object returns the summary; the full result
is `GLOSSARY(asset::property)`.

## Say when it does not apply

Where the asset does not fit, return a fact, not an error:
`applicable: false` and a `reason`. A text column has no outliers; the
reason can say that a date loaded as text needs a cast in the load
query. Keep `applicable` in the property's `required` list.

## A detector

A detector's query reads `annotations`: one row per author's value
for the test's property, `(subject, aspect, kind, test, actor,
actor_kind, current, written_at, body)`. `actor_kind` is `human`,
`agent` or `function`. `current` is false for a function's value
stored before the last change. `body` is a struct where every value
is a JSON object: read a field as `body['tolerance']`. A field no
value carries is an error at planning that names it.

The test's `THRESHOLD` is `$threshold`, NULL where the test has none.
Return one row per asset: `subject`, `state` (`green`, `yellow`,
`orange`, `red`) and `score` (0 to 1). No row means no result, not
green: keep a row for every `subject`.

```glossql
DECLARE TEST late_delivery_test ON late_deliveries BY (AGENT, HUMAN) DETECTOR rate_tolerance;
GLOSS late_deliveries ON deliveries AS $${"outcome": "a delivery arrives by the promised day",
  "tolerance": 0.05, "basis": "the service level in the carrier contract"}$$;
```

`rate_tolerance` reads `breach_rate` from the function's value and
`tolerance` from a person's annotation, else an agent's, else the
test's threshold: green at or under it, red above, yellow while
nothing was measured. Tests in full:
`skill://glossql-modeling/references/tests.md`.
