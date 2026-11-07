# Data tests

A data test checks that a number holds. It has four parts: an
expectation someone writes (a `FACT` annotation), a function that
measures the same property, a detector that scores the two against
each other, and `TESTS()`, which serves the result. Tests run when
they are read and never write into the data. The language reference is
[SPEC.md §7](https://github.com/glossdb/glossql/blob/main/SPEC.md).

## Write a test

```glossql
DECLARE ASPECT hours_reconcile WITH $${
  "type": "object", "required": ["outcome"],
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"},
                 "breach_rate": {"type": "number"}}
}$$ AS FACT ON TABLE WHEN entity = 'work log line';
GLOSS hours_reconcile ON work_logs AS $${
  "outcome": "Logged minutes match the order's recorded duration, exactly.", "tolerance": 0.0}$$;
DECLARE TEST hours_w ON hours_reconcile BY (AGENT, HUMAN)
  DETECTOR rate_tolerance THRESHOLD 0.0;
```

1. Declare the property, with an `outcome` in words and a `tolerance`.
2. Annotate the expectation on the table.
3. Declare a function whose `RETURNS` names the same property and
   whose result carries `breach_rate`
   ([measurements](measurements.md#declare-a-function)).
4. Declare the test (`DECLARE TEST`):
   - `BY` lists who may annotate the property: `AGENT`, `HUMAN`.
     Functions are not listed; a function takes part through its
     `RETURNS`.
   - `DETECTOR` names the scoring function (no `RETURNS`). The shipped
     `rate_tolerance` scores the measured `breach_rate` against the
     annotated `tolerance`.
   - `THRESHOLD` (0 to 1) is the score above which the values count as
     disagreeing.

A test collects, per asset, one value from each source: each function's
newest result, the agent's annotation, the person's annotation. Several
tests may be declared on one property; the result belongs to each test,
so one detector used by three tests gives three results.

## Set the expected rate

Write the expectation from what you measured, not zero. Nobody knows a
source's defects in advance: measure them when the table is loaded, and
the measured rate becomes the tolerance. The test is green today and
turns red when the source drifts.

- `breach_rate` is the share of rows that violate the expectation: 0.0
  means everything passes. It is compared upward against `tolerance`.
  A pass rate reported under this key scores a passing test red.
- `rate_tolerance` is one-sided: green at or under the tolerance, red
  above it, yellow while no function result exists.
- A function that reports 0.0 where the profile showed bad rows does
  not see them; fix the function's SQL.
- To also catch a load query that filters the bad rows away, declare
  your own detector that turns red on both sides.

## Read the results

```glossql
SELECT * FROM TESTS(orders.amount::behavior);
SELECT subject, band FROM TESTS(fin.trial_balance) WHERE band = 'red';
```

`TESTS()` returns `(subject, aspect, test, band, score,
computed_at, current, error)`:

- `band`: `green`, `yellow`, `orange`, `red` or `error`;
- `score`: the disagreement, 0 to 1;
- `current`: whether every function result the score read is current;
- `error`: why the detector could not answer, with band `error`. An
  error is not a result: it never withholds a value, and every other
  test still answers.

Filter with `WHERE`. With no argument, `TESTS()` covers the dataset in
use.

`GLOSSARY()` shows the same judgment as `state`:

| State | Meaning |
|---|---|
| `current` | the value holds |
| `contested` | the values differ and the score is above the threshold: the value is withheld, with band and score |
| `stale` | the data changed after the value was written; it is still served, and marked |
| `unassessed` | the property is required and nobody has annotated it; the row still appears |

Only values that differ can be contested. A single value never
contests itself: its band shows beside it, and the value is served.
Precedence is fixed: a person's value over an agent's over a
function's. The detector reports disagreement and never resolves it.

## What ships

The quality functions find what the pipeline, not the business, got
wrong. Ordinary growth, seasonality and business change are for the
metrics to show. Each function has an acceptance test against data
whose truth is known by construction ([functions](../reference/functions.md),
[methods](../methods/discovery.md)).

- **`detect_derivations`**: arithmetic identities among a table's
  numeric columns (`a = b·c`, `a = b+c`) with the rows that break them.
  A silently scaled slice breaks the identity on exactly its rows,
  where every other statistic mistakes it for a real price move. A
  confirmed identity, checked again on each load, is the standing test
  for subtle corruption.
- **`behavior_evidence`**: whether a numeric column is a stock or a
  flow, reconciled against the movements a related event table carries
  ([behavior](../methods/behavior.md)). Read it before annotating
  `behavior`.
- **`relationship_coherence`**: orphans and date order on every
  declared join ([relationships](relationships.md)).
- **`detect_relationships`, `column_profile`, `outlier_profile`,
  `temporal`, `detect_hierarchies`, `detect_grounding_collisions`**:
  the structure and the shape of each column.
- **Detectors**: `slot_entropy` scores agreement across a property's
  values; `rate_tolerance` scores a measured rate against its
  tolerance; `band_breach` scores the expected ranges
  ([expected ranges](../preview/expected-ranges.md), preview).

Measurements propose; they never decide. The agent reads them and
removes false positives; a person decides what no statistic can.

## Good practice

- **Watch per member, not only the total.** Two opposite changes leave
  a total flat; the slices show both.
- **Compare against the full history.** A sample makes long-tail
  members look new. On a living dimension some members are new every
  month; novelty is a rate.
- **Check for short periods.** An earlier period that a late source
  left thin, against the batch's own history, is the reader's call,
  not a score.
- **Turn a reconciliation you ran by hand into a test,** so it runs on
  every load.
