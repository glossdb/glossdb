# Tests: the built-in tests, rule views, tolerances

Read when a test is not green, or before declaring a test.

## What a test is

A test (`DECLARE TEST`) gives a state to a property of an asset:
`green`, `yellow`, `orange` or `red`. A function computes the
property's value; a detector turns the value into the state. The
results are rows:

```sql
SELECT view, test, subject, state, score, current, run FROM view_tests()
```

`view_tests()` lists, per view, the tests on the view and on the
tables and columns it reads, worst first. A table view and a single
value have rows too: the built-in join, orphan and completeness tests, the tests on
what they read and the tests you declared on them. A rule view has
its `rule_test`. `not_run` means no result exists yet; `current` is
false when something the stored result read changed after it was
stored. A test's result is stored per asset; the server computes the
ones out of date after each write. A detector that compares assets
with each other is refused (`cross_subject`): declare that test on
the table or the dataset that holds them. `run` is the
statement that computes the test's property again. It is empty where
no function measures it: `role_test`, `unit_test` and
`additivity_test` compare an agent's and a person's annotation, and a
test on a result an actor stores (about the dataset) is not run by
the server. `TESTS(asset)` gives the same states for any
asset. A test that is not green is a `test` row of `next`, on a view,
a table, a column or the dataset alike: `must` where it is red,
`should` otherwise. `open` is the test's name and its finding,
`statement` its fix. Where the check returns no
`fix`, the statement is the check to run again and, for a red test of
your own, the annotation that records an accepted rate.

## The built-in tests

The server runs these after a call that defines a view, annotates
what a test reads, or loads a table the view reads. `join_test`,
`orphan_test` and `relationship_test` run on every view the dataset
serves (a table, a single value, a metric), and `completeness_test`
on each of its columns. `measure_additivity_test` and `series_test`
run on each metric, since only a metric has a measure and a series.
`rule_test` runs on each rule view. A plain view gets none. The
server also runs what the tests read first:
a profile of each column the view joins on and of each column it
serves, and the check of each relationship between the tables it reads.

| Test | Red when | The usual fix |
|---|---|---|
| `join_test` | the view joins two tables on columns whose values repeat on both sides, so the join multiplies rows; or it reads an effective-dated table without both of its validity dates, so a row counts once per version | reduce one side to one row per key before the join; bound both dates in the join |
| `orphan_test` | rows on a declared relationship the view joins over find no parent: an inner join drops them, an outer join keeps them with empty parent columns | fix the load (trim, pad, cast the key), or load the missing parents |
| `completeness_test` | a load or a new definition emptied a column the view serves: its share of empty values rose by more than 0.1. It stays red until the column is filled again or the rate is accepted | where a table column it is computed from emptied too, fix the source or the load query; else correct the column's expression in the definition. Accept a rate that is right with `tolerance` on `completeness_check` on that column: the other columns stay held to 0.1 |
| `measure_additivity_test` | the value column does not say how it adds up, or says additive where the SQL computes a ratio, an average or a distinct count | correct `additivity` in the definition |
| `relationship_test` | never red; `yellow` where a join between two loaded tables has no declared relationship | the `DECLARE RELATIONSHIP` its fix names |
| `series_test` | a metric serves no series: no column carries role `timestamp` or `measure`, or the period column has no grain | the annotation its fix names, such as `time_grains` |
| `rule_test` | a rule view returns more rows than a person accepted | fix the load or the definition the rule reads; a person accepts a count |
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

## A rule of your own: a rule view

A rule the data must hold is a view of the rows that break it. One
statement, no more:

```glossql
GLOSS booking_has_card ON workshop AS $${"kind": "rule",
  "sql": "SELECT b.booking_id FROM bookings b LEFT JOIN job_cards c ON c.card_id = b.card_id WHERE c.card_id IS NULL",
  "meaning": "every booking names a job card", "tags": ["job card"]}$$;
```

- `rule_test` runs on it after every write, with no further
  statement. It is green while the view returns no row, red while it
  returns rows: a `must` row of `next` with the count and the first
  rows.
- The view's `meaning` states the rule; the finding quotes it.
- Select the columns that name a row (its key) and those that show
  why it breaks the rule.
- A red rule closes in one of two ways. Fix the load query or the
  definition of a view the rule reads. Or a person accepts the count
  of rows as it is, with the reason: `next` hands the statement, and
  only a person may write it.

```glossql
GLOSS rule_check ON workshop.booking_has_card AS $${"accepted": 3, "basis": "three bookings before the card system started, confirmed by the workshop lead"}$$;
```

The test stays green while the view returns no more rows than the
person accepted.

## A rate with a tolerance: a test of your own

Where a share of rows may break the rule (5% of deliveries late), the
test needs a tolerance. That takes five statements:

1. **A property for the expectation**, declared `AS FACT ON TABLE`,
   or `ON COLUMN` for one column. Its schema holds what a person
   states (`outcome`, `tolerance`, `basis`) and what the check
   returns (`breach_rate`, `finding`). Leave `required` out: the
   check's result is validated against the same schema.
2. **A function that computes it**, with `RETURNS <property>`.
3. **The test**, with `BY (AGENT, HUMAN)`, which names who may
   annotate the property, and `DETECTOR rate_tolerance`.
4. **The expectation, annotated on the asset** the rule holds for.
5. **A first run** of the function on the table (`FROM <table>`) or
   the column (`FROM <table>.<column>`).

```glossql
DECLARE PROPERTY hours_match WITH $${"type": "object",
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
  "tolerance": 0.02, "basis": "the workshop lead allows a correction a day"}$$;
SELECT hours_match_check() FROM bookings;
```

- **The annotation sets the test.** The test is on the assets that
  carry the expectation and on no other. `next` counts it there. One
  property can hold for several assets: annotate each, and run the
  function on each.
- **`breach_rate` is the share of rows that break the rule.** 0.0
  passes. A pass rate under that name reads red.
- **`tolerance` is the share of rows that may break the rule.**
  `rate_tolerance` is green at or under the tolerance, red above it,
  and `yellow` while the function has not run. It reads a person's
  tolerance first, then yours, then the test's `THRESHOLD`, then 0.0.
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
match a second route to the same number. Each is a rule view first.
A check you ran by hand is right today; as a rule view it is run
again after every write.

A property declared `AS MEASUREMENT` holds only what a function
returns, such as a profile. It carries no expectation, so nobody can
accept a rate on one asset. Use it for a test only where the test has
a detector of your own that needs no tolerance.
