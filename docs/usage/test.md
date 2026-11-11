# Test

A test is a statement about the data that is checked against the
data. It has a state, and the state is read again after each load.

| State | Meaning |
|---|---|
| `green` | holds |
| `yellow` | cannot be judged yet: the evidence is not stored |
| `orange` | a middle state a detector of your own may return |
| `red` | does not hold |
| `error` | the detector failed; the text is in `error` (`TESTS()`) |
| `not_run` | expected on a metric and not run yet (`view_tests()`) |

## The built-in tests

Each metric gets four tests, on the tables its definition scans:

| Test | Checks | Red when |
|---|---|---|
| `fan_out_test` | join fan-out | the definition joins two tables on columns whose values repeat on both sides, so the join multiplies rows |
| `orphan_test` | referential integrity on the declared relationships between the scanned tables | rows find no parent; the score is the highest orphan rate |
| `measure_additivity_test` | the additivity of the value column | none is stated, or a ratio, an average or a distinct count is marked as summable |
| `validity_test` | an effective-dated table (annotated `validity` with `valid_from`, `valid_to`) | the definition reads it without bounding both validity dates |

The server runs them after a call that defines the metric, annotates
its columns or loads a table it scans. They read the definition's
lineage and stored measurements: `column_profile()` on the join
columns, `relationship_coherence()` on the dataset. A test whose
evidence is missing is `yellow` and its `reason` names the
measurement to run. The four run on metrics. A table and a single
value carry the tests on what they read and the tests you declare on
them.

## Read the results

```sql
SELECT view, test, subject, state, score, run FROM view_tests();
```

`view_tests()` lists each test on each view and on the tables and
columns it reads, worst first. `evidence` holds the check's result,
`run` the statement that runs it again. `TESTS()` is the language's
own read, for any asset:

```glossql
SELECT subject, test, state, score, current FROM TESTS() WHERE state <> 'green';
```

## A test brings its finding and fix

A built-in test's result carries `finding`, one sentence on what is
wrong and what it does to the number, and `fix`, the statement that
settles it. `next` serves both:

```sql
SELECT asset, state, open, cause, statement FROM next WHERE step = 'test';
```

```
orphan_test: 4.6% of rows on sales.orders.customer_id -> sales.customers.customer_id
find no parent: an inner join drops them, an outer join counts them under no member
```

`cause` says what the newest load changed in the tables the metric
reads.

## Accept a result

Fix the load or the definition. Or accept the measured rate, with the
reason, as a tolerance on the metric. A person's tolerance outranks an
agent's.

```glossql
GLOSS orphan_check ON plant.downtime AS $${"tolerance": 0.02,
  "basis": "two decommissioned machines are not in the machine register"}$$;
```

The test is green while the rate stays at or under the tolerance, and
red when the source drifts past it.

## Write your own test

A test of your own has three parts: the expectation, the check that
measures it, and the test that scores one against the other.

```glossql
DECLARE ASPECT reading_filled WITH $${
  "type": "object",
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"},
                 "breach_rate": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE WHEN entity = 'one row per sensor reading';

DECLARE TEST reading_filled_test ON reading_filled BY (AGENT, HUMAN)
  DETECTOR rate_tolerance THRESHOLD 0.0;

DECLARE FUNCTION reading_filled_check FOR plant AS $$
  SELECT 'share of readings without a value' AS outcome,
         CASE WHEN count(*) = 0 THEN 0.0
              ELSE count(*) FILTER (WHERE value IS NULL) / count(*)::DOUBLE END AS breach_rate
  FROM readings
$$ RETURNS reading_filled;

GLOSS reading_filled ON readings AS $${"outcome": "each reading carries a value", "tolerance": 0.01}$$;
SELECT reading_filled_check() FROM readings;
```

1. **The property** (`AS FACT`) holds the expectation: an `outcome` in
   words and a `tolerance`. `WHEN` limits it to the tables it is
   about; without it the property is required on each table.
2. **The test** (`DECLARE TEST`) names who may annotate the property
   (`BY`), the detector and the threshold. Declare it before the
   annotation.
3. **The check** is a function whose `RETURNS` names the same
   property and whose result carries `breach_rate`: the share of rows
   that violate the expectation. 0.0 passes.
4. **The detector** `rate_tolerance` compares the two: green at or
   under the tolerance, red above it, yellow while no check result
   exists. It is one-sided.

Set the tolerance to the rate you measured, not to zero. The test is
then green today and red when the source drifts. A check that also
returns `finding` and `fix` has both served in `next`, as the built-in
tests do.

The result lists under each view that reads the table in
`view_tests()`, and in `TESTS()`.

## Tests on annotations

The `kpi` kit declares a test on each of its properties. `role_test`,
`additivity_test` and `unit_test` score where an agent's and a
person's values differ (`value_entropy`, threshold 0.7). Above the
threshold `GLOSSARY()` withholds the value and reports `conflict`.
