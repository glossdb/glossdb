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
tables and columns it reads, worst first. A table view and a single
value have rows too: the built-in join and orphan tests, the tests on
what they read and the tests you declared on them. `not_run` means no result exists yet; `current` is
false when the data changed after the result was stored. `run` is the
statement that measures the test's property again. It is empty where
no function measures it: `role_test`, `unit_test` and
`additivity_test` compare an agent's and a person's annotation, and a
test on a result an actor stores (about the dataset, or a plan) is
not run by the server. `TESTS(asset)` gives the same states for any
asset. A test that is not green is a `test` row of `next`, on a view,
a table, a column or the dataset alike: `must` where it is red,
`should` otherwise. `open` is the test's name and its finding,
`statement` its fix. Where the check returns no
`fix`, the statement is the check to run again and, for a red test of
your own, the annotation that records an accepted rate.

## The built-in tests

The server runs these after a call that defines a view, annotates
what a test reads, or loads a table the view reads. `join_test` and
`orphan_test` run on every view: a table view, a single value, a
metric. `measure_additivity_test` runs on each metric, since only a
metric has a measure. The server also runs what the tests read first:
a profile of each column the view joins on, and the check of each
relationship between the tables it reads.

| Test | Red when | The usual fix |
|---|---|---|
| `join_test` | the view joins two tables on columns whose values repeat on both sides, so the join multiplies rows; or it reads an effective-dated table without both of its validity dates, so a row counts once per version | reduce one side to one row per key before the join; bound both dates in the join |
| `orphan_test` | rows on a declared relationship the view joins over find no parent: an inner join drops them, an outer join keeps them with empty parent columns | fix the load (trim, pad, cast the key), or load the missing parents |
| `measure_additivity_test` | the value column does not say how it adds up, or says additive where the SQL computes a ratio, an average or a distinct count | correct `additivity` in the definition |
| `grain_test` | on a loaded table whose `entity` states a `grain`: a key repeats in the loaded rows | keep one row per key in the load query, or state the grain the rows have |

`orphan_test` reads declared relationships only: `next` lists each
join a view makes between two loaded tables with no declared
relationship, with the `DECLARE RELATIONSHIP` to run. `join_test`
judges a join on several columns on its key as a whole; where no
unique column and no stated grain says which side holds each key
once, it is `yellow` and its fix states the grain. It judges a join on
an effective-dated table by its validity dates once the table is
marked as such:

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

Four statements and one run:

1. **A property for the expectation**, declared `AS FACT ON TABLE`,
   or `ON COLUMN` for one column. Its schema holds what a person
   states (`outcome`, `tolerance`, `basis`) and what the check
   returns (`breach_rate`, `finding`). Leave `required` out: the
   check's result is validated against the same schema.
2. **A function that measures it**, with `RETURNS <property>`.
3. **The test**, with `BY (AGENT, HUMAN)`, which names who may
   annotate the property, and `DETECTOR rate_tolerance`.
4. **The expectation, annotated on the asset** the rule holds for.
5. **A first run** of the function on the table (`FROM <table>`) or
   the column (`FROM <table>.<column>`).

```glossql
DECLARE ASPECT hours_match WITH $${"type": "object",
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"}, "basis": {"type": "string"},
                 "breach_rate": {"type": "number"}, "finding": {"type": ["string", "null"]}}}$$ AS FACT ON TABLE;
DECLARE FUNCTION hours_match_check FOR workshop AS $$
  SELECT count(*) FILTER (WHERE booked_hours <> card_hours) / greatest(count(*), 1)::DOUBLE AS breach_rate,
         CASE WHEN count(*) FILTER (WHERE booked_hours <> card_hours) > 0
              THEN count(*) FILTER (WHERE booked_hours <> card_hours) || ' bookings differ from the job card' END AS finding
  FROM bookings
$$ RETURNS hours_match;
DECLARE TEST hours_match_test ON hours_match BY (AGENT, HUMAN) DETECTOR rate_tolerance;
GLOSS hours_match ON bookings AS $${"outcome": "booked hours match the hours on the job card",
  "tolerance": 0.0, "basis": "the job card is the source of the booking"}$$;
SELECT hours_match_check() FROM bookings;
```

`skill://glossql/SKILL.md` shows a table test and a column test
whole, `define.md` one check for a data contract.

- **The annotation sets the test.** The test is on the assets that
  carry the expectation and on no other. `next` and
  `workspace_status` count it there. One property can hold for
  several assets: annotate each, and run the function on each.
- **`breach_rate` is the share of rows that break the rule.** 0.0
  passes. A pass rate under that name reads red.
- **`tolerance` is the share of rows that may break the rule.** State
  0.0 where the rule allows no exception. `rate_tolerance` is green
  at or under the tolerance, red above it, and `yellow` while the
  function has not run. It reads a person's tolerance first, then
  yours, then the test's `THRESHOLD`, then 0.0.
- **A test states the rule.** Where the data breaks the rule the test
  is red, and it stays red until the data is right or a person
  accepts the rate. Do not set the tolerance at what you measured to
  make the test green: that hides the defect.
- **A red test closes in one of two ways.** Fix the load query or the
  view's definition and run the check again. Or a person accepts the
  measured rate: the same property, annotated on the same asset, with
  the rate as `tolerance` and who accepted it and why as `basis`.
  `next` gives both statements. A person writes that annotation in
  the console or over the query endpoint, and theirs outranks yours.
  Where you record it for them, name them in `basis`.
- Until a person has accepted a rate, report the red test as a
  finding with its size.
- **Return `finding` beside `breach_rate`.** A result with one
  column is stored as a bare value and does not fit the property's
  object schema. `finding` is one sentence on what is wrong; `next`
  shows it. A field `fix`, a statement as text, is shown as the row's
  statement; add it to the property's schema to use it.
- **The subject is the asset the function is run on**: a view, a
  table, or a column. Run the function once. After a load of a table
  the view reads, the server runs it again.
- A test on a view, or on a column of a view, shows in `next` for
  that view. So does a test on a table or column a view reads.
- One function returns one property. A second rule is a second
  property, function and test.
- The function's body is one SQL query
  (`skill://glossql-functions/SKILL.md`).
- `GLOSSARY()` lists the property as `missing` on the assets that do
  not carry it. That is the catalog's coverage read. It asks nothing
  of you: the test is only where you set it.

What to test: a key that must be unique, a column that must be
filled, a code that must be in its code table, a total that must
match a second route to the same number. A check you ran by hand is
right today; as a test it is run again at each load.

A property declared `AS MEASUREMENT` holds only what a function
returns, such as a profile. It carries no expectation, so nobody can
accept a rate on one asset. Use it for a test only where the test has
a detector of your own that needs no tolerance.
