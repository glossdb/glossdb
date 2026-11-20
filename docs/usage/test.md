# Test

A test is a statement about the data that is checked against the
data. It has a state, stored per asset, and the server computes it
again after each write that changes what it read.

| State | Meaning |
|---|---|
| `green` | holds |
| `yellow` | cannot be judged yet: the evidence is not stored |
| `orange` | a middle state a detector of your own may return |
| `red` | does not hold |
| `error` | the detector failed; the text is in `error` (`TESTS()`) |
| `not_run` | expected on a view and not run yet (`view_tests()`) |

## The built-in tests

Each view the dataset serves (a table, a single value, a metric)
gets the join, orphan and relationship tests, on the tables its
definition scans, and the completeness test on each column it serves;
each metric also gets the additivity and series tests; each rule view
gets the rule test; each loaded table whose `entity` states a `grain`
gets the grain test. A plain view gets none:

| Test | Checks | Red when |
|---|---|---|
| `join_test` | join fan-out, and effective-dated tables (annotated `validity` with `valid_from`, `valid_to`) | the definition joins two tables on columns whose values repeat on both sides, so the join multiplies rows; or it reads an effective-dated table without bounding both validity dates, so a row counts once per version. A join on several columns is judged on its key as a whole: a side holds each key once where one of its columns is unique or its columns hold the grain its table states; where neither side does, the test is `yellow` and its fix states the grain |
| `orphan_test` | referential integrity on the declared relationships between the scanned tables | rows find no parent; the score is the highest orphan rate |
| `completeness_test` | a column the view serves, against its share of empty values (NULL) before a load or a new definition emptied it. One result per column: a column can be unusable while the others are fine | the column's share of empty values rose by more than the threshold, 0.1, over its last share within it. The score is the rise. The finding gives the share before and now, and the cause: a load, where a table column it is computed from emptied too, else the definition. The test stays red after later loads until the column is filled again or a person accepts the rate on that column. A column that rises by less per load, or was mostly empty before, stays green |
| `relationship_test` | a declared relationship for each join between two loaded tables | never red: where a join has none, the test is `yellow` and its fix declares it, from the side that repeats the key to the side that holds it once, where a profile or a stated grain says which side that is |
| `measure_additivity_test` | the additivity of the value column | none is stated, or a ratio, an average or a distinct count is marked as summable |
| `series_test` | the metric serves a series | no column carries role `timestamp` or role `measure`, or the period column has no grain; the fix is the annotation or the function run that is missing |
| `rule_test` | a rule view: each row it returns breaks the rule its `meaning` states | the view returns more rows than a person accepted (none, until one did); the finding gives the count and the first rows |
| `grain_test` | the grain the table's `entity` states, at each load | a key repeats in the loaded rows, such as a line sent twice; the score is the share of rows past the first per key |

The server runs them after a call that defines the view, annotates
what a test reads or loads a table the view scans. They read the
definition's lineage and stored results: `column_profile()` on
the join columns and on each column the view serves, with the values
each profile held before, `relationship_coherence()` on each declared
relationship between the scanned tables. The server computes those
first, from what each test's check reads. A test whose evidence is
missing is `yellow` and its `reason` names the function to run.
The harmonise kit (preview) adds `contract_test` on a target view
that carries a data contract
([reads](../reference/reads.md#the-harmonise-kit-preview)).

## Read the results

```sql
SELECT view, test, subject, state, score, run FROM view_tests();
```

`view_tests()` lists each test on each view and on the tables and
columns it reads, worst first. `evidence` holds the check's result,
`run` the statement that runs it again; it is empty for a test that
compares annotations, which no function computes. A test on a result
about the dataset as a whole is a row too, with an empty `run`: an
actor stores that result, and the server does not compute it after a
write. `TESTS()` is the language's own read, for any asset:

```glossql
SELECT subject, test, state, score, current FROM TESTS() WHERE state <> 'green';
```

A test's result is stored per asset and test, with what it read: the
asset's values of the property, the asset's definition, and the
declarations of the test and its detector. After each write the
server runs `SELECT <test>() FROM <dataset>` for each test whose
results are missing or out of date; the statement computes those
assets alone. `current` is false while a stored result is out of
date. A check that reads other functions' results, such as a profile,
runs again when one of those results changes value
([how results stay current](../reference/dependencies.md)). A test
judges each asset alone. A detector that compares assets with each
other is refused (`cross_subject`): declare such a test on the table
or the dataset that holds the assets.

A red test is a failed test. It does not withhold a value: only two
values of one property that differ beyond the test's threshold are a
`conflict` ([tests on annotations](#tests-on-annotations)). A test
with nothing to check is green, and its `reason` says why: `orphan_test`
on a view that joins over no declared relationship, for example.

## A test brings its finding and fix

A built-in test's result carries `finding`, one sentence on what is
wrong and what it does to the number, and `fix`, the statement that
settles it. `next` serves both, for a test on a view, a table, a
column or the dataset, whatever kit declared it. A red test is a
`must`: served data is wrong. A test not run, yellow, orange or failed
is a `should`. A red test of your own without a `fix` gets the check
to run again and the annotation that records an accepted rate:

```sql
SELECT level, asset, state, open, statement FROM main.next WHERE kind = 'test';
```

```
orphan_test: 4.6% of rows on sales.orders.customer_id -> sales.customers.customer_id
find no parent: an inner join drops them, an outer join keeps them with empty parent columns
```

What the newest load changed in each table is a read of its own:

```sql
SELECT table_name, cause FROM load_changes();
```

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

A rule of your own is a rule view: a query whose rows break the rule,
in one statement. `rule_test` runs on it after every write, with no
further statement.

```glossql
GLOSS reading_has_machine ON plant AS $${"kind": "rule",
  "sql": "SELECT r.reading_id, r.machine_id FROM readings r LEFT JOIN machines m ON m.machine_id = r.machine_id WHERE m.machine_id IS NULL",
  "meaning": "every reading comes from a machine in the register", "tags": ["machine"]}$$;
```

While the view returns rows, the test is red and a `must` row of
`next`, with the count, the first rows, the read of the rows and the
statement by which a person accepts the count as it is. Only a person
writes it, in the console or over the query endpoint; the test stays
green while the view returns no more rows than they accepted:

```glossql
GLOSS rule_check ON plant.reading_has_machine AS $${"accepted": 2,
  "basis": "two test rigs log readings and are not in the register"}$$;
```

A rule that allows a share of rows, such as 1% of readings without a
value, needs a tolerance. That test of your own takes five
statements: a property for the expectation, a function that computes
the share of rows that break it, the test with the `rate_tolerance`
detector, the expectation annotated on the asset, and a first run. The
agents' skill teaches it
(`skill://glossql-modeling/references/tests.md`). A person accepts a
rate there as the same property on the same asset, with a higher
`tolerance` and the reason in `basis`. The results list under each
view that reads the table in `view_tests()`, and in `TESTS()`.

## Tests on annotations

The `kpi` kit declares a test on each of its properties. `role_test`,
`additivity_test` and `unit_test` score where an agent's and a
person's values differ (`value_entropy`, threshold 0.7). Above the
threshold `GLOSSARY()` withholds the value and reports `conflict`.
