# Tests: the built-in tests, tests of your own, tolerances

Read when a test is not green, or before declaring a test.

## What a test is

A test (`DECLARE TEST`) gives a state to a property of an asset:
`green`, `yellow`, `orange` or `red`. A function measures the
property; a detector turns the measurement into the state. The
results are rows:

```sql
SELECT view, test, subject, state, score, current, run FROM view_tests()
```

`view_tests()` lists, per view, the tests on the view and on the
tables and columns it reads, worst first. `not_run` means no result
exists yet; `current` is false when the data changed after the result
was stored; `run` is the statement that measures it. `TESTS(asset)`
gives the same states for any asset. A test that is not green is a
row of `next` under `test`, with the test's finding in `open` and a
fix in `statement`.

## The built-in tests

The server runs these on each metric after a call that defines it,
annotates it or its columns, or loads a table it reads. It also runs
what they read: a profile of each column the metric reads, and the
relationship check of the dataset.

| Test | Red when | The usual fix |
|---|---|---|
| `fan_out_test` | the metric joins two tables on columns whose values repeat on both sides, so the join multiplies rows | reduce one side to one row per key before the join |
| `orphan_test` | rows on a declared relationship the metric uses find no parent: an inner join drops them, an outer join counts them under no member | fix the load (trim, pad, cast the key), or load the missing parents |
| `validity_test` | the metric reads an effective-dated table without both of its validity dates, so a row counts once per version | bound both dates in the join |
| `measure_additivity_test` | the value column does not say how it adds up, or says additive where the SQL computes a ratio, an average or a distinct count | correct `additivity` in the definition |

`orphan_test` reads declared relationships only: declare the joins a
view uses. `validity_test` needs the table marked as effective-dated:

```glossql
GLOSS validity ON price_list AS $${"valid_from": "valid_from", "valid_to": "valid_to"}$$;
```

**Accepting a result.** Where the number is right as it is, record a
tolerance at or above the measured rate, with the reason. The
statement in `next` carries the rate. A person's tolerance outranks
yours, so they can overrule it:

```glossql
GLOSS orphan_check ON logistics.parcels_delivered AS $${"tolerance": 0.1, "basis": "depot 099 closed in 2025 and is not in the depot list"}$$;
```

Do not change a definition only to make a test green. Fix what is
wrong, or accept what is right and say why.

## A test of your own

Three statements and one run: a property for the result (`AS
MEASUREMENT ON TABLE`), a function that measures it, the test, and a
first run of the function. `skill://glossql/SKILL.md` step 4 and
`define.md` show it whole. With a rate you accept:

```glossql
DECLARE TEST weight_filled_test ON weight_filled DETECTOR rate_tolerance THRESHOLD 0.2;
```

- **`breach_rate` is the share of rows that break the rule.** 0.0
  passes. A pass rate under that name reads red.
- **`THRESHOLD` is the rate you accept.** `rate_tolerance` is green
  at or under it, red above it, and `yellow` while the function has
  not run. Measure the defect first and set the threshold at what you
  measured, so the test is green today and red when the source gets
  worse. A threshold of 0.0 where the data is known to be dirty is red
  from the start.
- **Return `finding` beside `breach_rate`.** A result with one
  column is stored as a bare value and does not fit the property's
  object schema. `finding` is one sentence on what is wrong; `next`
  shows it. A field `fix`, a statement as text, is shown as the row's
  statement.
- **The subject is the asset the function is run on**, here the view
  `clean_deliveries`. Run the function once. After a load of a table
  the view reads, the server runs it again.
- A test on a view, or on a column of a view, shows in `next` for
  that view. So does a test on a table or column a view reads.
- One function returns one property. A second rule is a second
  property, function and test.
- The function's body is one SQL query
  (`skill://glossql-functions/SKILL.md`).

What to test: a key that must be unique, a column that must be
filled, a code that must be in its code table, a total that must
match a second route to the same number. A check you ran by hand is
right today; as a test it is run again at each load.

## A test a person can set the tolerance of

Declare the property `AS FACT` with a `tolerance` in its schema. You
or a person annotate the expectation; the function measures the same
property; `rate_tolerance` compares the two. The person's tolerance
is used before yours, and both before the `THRESHOLD`.

```glossql
DECLARE ASPECT hours_match WITH $${"type": "object",
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"},
                 "breach_rate": {"type": "number"}, "finding": {"type": ["string", "null"]}}
}$$ AS FACT ON TABLE WHEN entity = 'workshop booking';
DECLARE TEST hours_match_test ON hours_match BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;
GLOSS hours_match ON bookings AS $${"outcome": "booked hours match the hours on the job card", "tolerance": 0.02}$$;
```

- `BY (AGENT, HUMAN)` names who may annotate the property. Declare
  the test before the annotation, or the annotation is refused.
- A `FACT` property with a test is required on every asset of its
  `ON` kind that a view reads, and shows as `missing` there. Narrow
  it with `WHEN <property> = '<value>'`, here to the tables whose
  `entity` is `workshop booking`.
- A rate above the tolerance withholds the value: `GLOSSARY()` shows
  the state `conflict` and the test is red.
