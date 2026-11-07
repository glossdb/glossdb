# Measurements

A function is one SQL query that measures the data: profiling, quality
screens, detection. A measurement function `RETURNS` a property and
runs over data. A detector has no `RETURNS` and scores how far the
values for a property agree ([data tests](data-tests.md)). Metrics are
neither: a metric is a `VIEW` property ([metrics](metrics.md)). The
language reference is [SPEC.md §6](https://github.com/glossdb/glossql/blob/main/SPEC.md);
the shipped functions are listed in [functions](../reference/functions.md).

## Declare a function

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

- `FOR` scopes the function to one dataset, or `GLOBAL` to all.
- The body is read-only SQL and can read anything a query can: tables,
  metrics by name, the catalog tables, the shipped aggregates.
- The output is validated against the returned property's JSON Schema
  and served as it is.
- The body is part of the declaration; there is no file. The shipped
  functions read back as examples: `SELECT script FROM functions`.
- A function takes no arguments; it is always called as `f()`. It reads
  what it needs inline: an annotation from the glossary, an earlier
  result from `measurements`.

What the returned property's kind makes of the function:

- **`MEASUREMENT`**: the function is the one source of that property's
  value.
- **`FACT`**: the function's result is one more value for the
  property, beside the agent's and the person's. This is the measuring
  half of a data test.

## Run a measurement

```glossql
SELECT outlier_profile() FROM work_orders.duration_min;
```

Running a function computes it at the current versions of everything
the statement resolved, and stores one row in `measurements` with what
the body actually read (`reads`) and at which version (`pin`).

- The stored row is served again, and marked `current`, while what it
  read is unchanged. A write to anything else, such as another table's
  load or an annotation the body never reads, does not make it stale.
- When something it read changes, the next run computes again. Old rows
  stay as a record of drift.
- A body that returns a `summary` object serves the summary when run;
  the full value is `GLOSSARY(subject::aspect)`.

Functions never write annotations, and no measurement writes a result
into the data.

## When a function does not apply

When the asset does not fit, the function answers `applicable: false`
with a reason that points to the cause, for example a date loaded as
text, which is a fix in the load query. A function that does not apply
because of the data's shape has found something too.

## Write a detector

A detector is named only in a test's `DETECTOR` clause. Its query runs
over `slots`: the test's collected values for its property, with
`speaker` and `current` beside each, and `body` typed by the values'
own JSON. The test's `THRESHOLD` is bound as `$threshold`. The query
returns one row per asset: `subject`, `band`, `score`. The engine adds
the test, its property and the time.
