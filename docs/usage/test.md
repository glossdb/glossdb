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
| `not_run` | expected on a view and not run yet (`view_tests()`) |

## The built-in tests

Each view gets the join and orphan tests, on the tables its definition
scans; each metric also gets the additivity test:

| Test | Checks | Red when |
|---|---|---|
| `join_test` | join fan-out, and effective-dated tables (annotated `validity` with `valid_from`, `valid_to`) | the definition joins two tables on columns whose values repeat on both sides, so the join multiplies rows; or it reads an effective-dated table without bounding both validity dates, so a row counts once per version |
| `orphan_test` | referential integrity on the declared relationships between the scanned tables | rows find no parent; the score is the highest orphan rate |
| `measure_additivity_test` | the additivity of the value column | none is stated, or a ratio, an average or a distinct count is marked as summable |

The server runs them after a call that defines the view, annotates
what a test reads or loads a table the view scans. They read the
definition's lineage and stored measurements: `column_profile()` on
the join columns, `relationship_coherence()` on each declared
relationship between the scanned tables. The server computes those
first, from what each test's check reads. A test whose evidence is
missing is `yellow` and its `reason` names the measurement to run. A
table view and a single value carry the join and orphan tests, the
tests on what they read and the tests you declare on them.

## Read the results

```sql
SELECT view, test, subject, state, score, run FROM view_tests();
```

`view_tests()` lists each test on each view and on the tables and
columns it reads, worst first. `evidence` holds the check's result,
`run` the statement that runs it again; it is empty for a test that
compares annotations, which no function measures. A test on a result
about the dataset as a whole or about a plan is a row too, with an
empty `run`: an actor stores that result, and the server does not
compute it after a write. The preview tests `range_test` and
`plan_test` come in this way once their result is stored
([outlook](outlook.md)). `TESTS()` is the language's own read, for
any asset:

```glossql
SELECT subject, test, state, score, current FROM TESTS() WHERE state <> 'green';
```

## A test brings its finding and fix

A built-in test's result carries `finding`, one sentence on what is
wrong and what it does to the number, and `fix`, the statement that
settles it. `next` serves both, for a test on a view, a table, a
column or the dataset, whatever kit declared it. A red test is a
`must`: served data is wrong. A test not run, yellow, orange or failed
is a `should`. A red test of your own without a `fix` gets the check
to run again and the annotation that records an accepted rate:

```sql
SELECT level, asset, state, open, cause, statement FROM next WHERE kind = 'test';
```

```
orphan_test: 4.6% of rows on sales.orders.customer_id -> sales.customers.customer_id
find no parent: an inner join drops them, an outer join keeps them with empty parent columns
```

`cause` says what the newest load changed in the tables the view
reads.

## Accept a result

Fix the load or the definition. Or accept the measured rate, with the
reason, as a tolerance on the view. A person's tolerance outranks an
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
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"}, "basis": {"type": "string"},
                 "breach_rate": {"type": "number"}, "finding": {"type": ["string", "null"]}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION reading_filled_check FOR plant AS $$
  SELECT CASE WHEN count(*) = 0 THEN 0.0
              ELSE count(*) FILTER (WHERE value IS NULL) / count(*)::DOUBLE END AS breach_rate,
         CASE WHEN count(*) FILTER (WHERE value IS NULL) > 0
              THEN count(*) FILTER (WHERE value IS NULL) || ' readings carry no value' END AS finding
  FROM readings
$$ RETURNS reading_filled;

DECLARE TEST reading_filled_test ON reading_filled BY (AGENT, HUMAN)
  DETECTOR rate_tolerance;

GLOSS reading_filled ON readings AS $${"outcome": "each reading carries a value",
  "tolerance": 0.01, "basis": "a sensor drops out for a few seconds per shift"}$$;
SELECT reading_filled_check() FROM readings;
```

1. **The property** (`AS FACT`) holds the expectation: an `outcome`
   in words, a `tolerance` (the share of rows that may break it) and
   a `basis` (why). The same schema holds what the check returns, so
   it lists no `required` field.
2. **The check** is a function whose `RETURNS` names the same
   property and whose result carries `breach_rate`: the share of rows
   that break the expectation. 0.0 passes. `finding` is one sentence
   on what is wrong.
3. **The test** (`DECLARE TEST`) names who may annotate the property
   (`BY`) and the detector.
4. **The annotation** sets the test on that asset: a table, or a
   column for a property declared `ON COLUMN`. The test is on the
   assets that carry the expectation and on no other; `next` and
   `workspace_status` count it there.
5. **The detector** `rate_tolerance` compares the two: green at or
   under the tolerance, red above it, yellow while no check result
   exists. It reads a person's tolerance first, then an agent's, then
   the test's `THRESHOLD`, then 0.0. It is one-sided.

A test states the rule. Where the data breaks it, the test stays red
until the load query or the data is fixed, or a person accepts the
measured rate. The person annotates the same property on the same
asset, with the rate as `tolerance` and the reason in `basis`:

```glossql
GLOSS reading_filled ON plant.readings AS $${"outcome": "each reading carries a value",
  "tolerance": 0.03, "basis": "line 2 runs the old sensors until the refit in May"}$$;
```

A tolerance set at the measured rate without that decision hides the
defect. `next` lists a red test with its `finding`, the check to run
again and that annotation to fill in. A check that also returns `fix`
has it served as the row's statement, as the built-in tests do.

A property declared `AS MEASUREMENT` holds only a function's result,
such as a profile. It carries no expectation and no tolerance per
asset, so a test of your own is declared on a `FACT` property.

The result lists under each view that reads the table in
`view_tests()`, and in `TESTS()`.

## Tests on annotations

The `kpi` kit declares a test on each of its properties. `role_test`,
`additivity_test` and `unit_test` score where an agent's and a
person's values differ (`value_entropy`, threshold 0.7). Above the
threshold `GLOSSARY()` withholds the value and reports `conflict`.
