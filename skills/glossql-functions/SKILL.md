---
name: glossql-functions
description: Write a function for a glossql workspace — measurements (RETURNS an aspect, a query over the data), computed values for FACT aspects, and detectors (no RETURNS, a query over the values a test collects). Every body is one SQL query. Use when a shipped measurement does not fit this dataset, when a validation needs its measuring half, or when debugging a function that abstains.
---

# Writing functions

A function is declared through the MCP interface and run by the server. Every
body is **one SQL query** the engine plans and runs (read-only). Two
roles, told apart by shape:

- **A measurement or a computed value** — it `RETURNS` an aspect, and its output
  is validated against that aspect's schema. Its query runs over data,
  composing everything a read can. Filling a MEASUREMENT aspect makes
  it a measurement; filling a FACT aspect makes it a **computed value**: one
  more value for that aspect, beside the agent's and the person's. The
  measuring half of a validation is a computed value.
- **A detector** — no `RETURNS`. Named in a test's (`TEST`)
  `DETECTOR` clause; its query runs over the test's `slots` relation,
  the values it collects.

## Read the closest one first

The reference library ships in every workspace and the body is a
column, so the library is readable through the tool:

```sql
SELECT name, returns FROM functions ORDER BY name
```

```sql
SELECT script FROM functions WHERE name = 'rate_tolerance'
```

Read the one nearest your task before writing:

- `profile` — a measurement whose body is SQL over the engine's
  `profile` aggregate; the shape every new measurement takes.
- `outliers` — a measurement composing another measurement's
  aggregate inline (its fences derive from `profile(v)` in the same
  statement).
- `slot_entropy` — a detector.
- `rate_tolerance` — a detector over the collected values (a written
  expectation against a computed value), which is the usual validation
  shape.

## Declaration

The body rides the statement — there is no path and no file. A
measurement:

```glossql
DECLARE FUNCTION on_time_check FOR ops AS $$
  SELECT
    'a work order completes by its promised date; a late close is the exception' AS outcome,
    CASE WHEN count(*) = 0 THEN 0.0
         ELSE CAST(count(*) FILTER (WHERE completed_at > promised_at) AS DOUBLE) / count(*)
    END AS breach_rate
  FROM work_orders
$$ RETURNS on_time_completion;
```

- `FOR` scopes to a dataset, or `GLOBAL`.
- `RETURNS` names the aspect the output fills, validated against that
  aspect's JSON Schema when the measurement runs.
- The body composes anything a read can, inline: tables, metric
  definitions by their names, the catalog tables as plain
  tables, and the shipped `profile` aggregate beside the engine's own
  (`mad` and `entropy` ride inside its struct:
  `profile(v)['numeric']['mad']`, `profile(v)['entropy']`). An annotated
  value is a read over the glossary; another measurement's stored
  value, a read over `measurements`; a statistic, the same aggregate
  computed in place.
- `$subject` arrives as a string literal wherever the body writes it;
  `subject_column($subject)` is the subject's column as a relation
  named `v`, for column-grain functions whose body cannot know the
  column's name.
- The result is stored by a fixed rule: one row × one column → the value;
  one row → an object of its columns; many rows → an array of row
  objects. NULL keys are omitted. Size it like a claim — something that
  wants to be a table is a read, not a measurement.
- The body cannot contain `$$` — it would close the statement early.

The name is the key, workspace-wide: one row per name, and a
re-declare **replaces** it — old measurements sit at pins that no
longer resolve, so the next run recomputes. Take a shipped name only
on purpose: the library's own body is kept nowhere else in the
workspace, so replacing `profile` costs the tested one until a
rebuild installs it again. For a MEASUREMENT this is the only route
(a second name returning the same aspect is refused); for anything
else, use your own name.

## Abstain, never throw

When the subject does not fit, the answer is a fact, not a failure:
`applicable: false` with a `reason` — a text column has no outliers,
and the reason names the lead (a date loaded as text is a typing gap
in the load query, not a dead end). Keep `applicable` in the aspect's
`required`. An abstention that is *starvation* rather than a
mismatch is worth saying in the read-back — it is a finding about
the data's shape.

## Detectors

A detector's query plans over the **`slots`** relation — one row per
author's value on the test's aspect:
`(subject, aspect, kind, test, actor, speaker, current, written_at, body)`.
`speaker` is `human` | `agent` | `function`; `current` is false for a
function's value stored before the last write — it still counts, and
`TESTS()` marks the result. `body` arrives **typed**:
when every body is a JSON object (an aspect's slots share its
schema, so they do), the column is a struct and fields read as
`body['tolerance']`, nested arrays through `unnest(body['metrics'])`;
anything else leaves `body` as text. A field no value carries is a
plan-time error naming it — which is the read telling you what is
missing (an expectation annotation, usually), not a case to code
around.

The test's `THRESHOLD` binds as `$threshold` (NULL when the test
declares none — coalesce your default). The query returns one row per
subject with `subject`, `band` (green|yellow|orange|red), and `score`
(0..1); the engine completes the result row with the test, its
aspect, and its own clock. One query answers every subject — group by
`subject`, and keep a row for subjects whose values say nothing (a
LEFT JOIN back to `SELECT DISTINCT subject FROM slots`), because no
row means no result, not green.

```glossql
DECLARE FUNCTION spread_bands FOR ops AS $$
  WITH s AS (
    SELECT subject,
           CASE WHEN count(*) <= 1 THEN 0.0
                ELSE (count(DISTINCT body['value']) - 1.0) / (count(*) - 1.0)
           END AS score
    FROM slots GROUP BY subject
  )
  SELECT subject, score,
         CASE WHEN score = 0.0 THEN 'green'
              WHEN score <= coalesce($threshold, 1.0) THEN 'yellow'
              ELSE 'red' END AS band
  FROM s
$$;
```

Judgment lives in detectors and in read policy, never in results — no
measurement writes a judgment into data.

```glossql
DECLARE TEST on_time_w ON on_time_completion BY (AGENT, HUMAN)
  DETECTOR rate_tolerance THRESHOLD 0.0;
```

## A bespoke function is the installation's recorded thinking

A workspace-scoped function (`FOR <dataset>`) holds method specific
to this data. When a shipped measurement starves on this dataset's shape — a
derivation screen over columns that only reconcile through a document
table, say — a function that encodes how the question is decided
*here* beats a pile of hand judgments: it is versioned,
re-runnable, and its abstentions stay as honest as the library's.

## Running

```glossql
SELECT outlier_profile() FROM work_orders.duration_min;
```

A run computes at the read's pin — the data and declarations the
statement resolved — and stores a `measurements` row; the same pin serves
it back, and any input moving recomputes. A body carrying a `summary`
object serves the summary alone — the full body reads back through
`GLOSSARY(subject::aspect)`, uncapped.
