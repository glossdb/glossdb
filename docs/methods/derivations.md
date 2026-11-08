# Derivations

`detect_derivations` finds arithmetic identities among a table's
numeric columns, row by row: `a = b * c` and `a = b + c`. It reports
each candidate with its support, its violation count and its match
rate. It runs on a table: `SELECT detect_derivations() FROM orders`.

## What it answers

A scoped corruption and a real business change move a metric the same
way. A slice whose amounts were silently scaled shifts the mean, the
quantiles and the distribution exactly as a price change would. No
statistic over one column tells the two apart.

An identity does. `line_amount = units * unit_price` holds on every row
of clean data. When one operand is scaled, the identity breaks on
exactly the corrupted rows. On the clean test corpora the violation
rate is 0.0; on a corrupted one it equals the share of corrupted rows.
A confirmed identity, checked again on every load, separates "the
pipeline broke" from "the business changed".

## How it works

1. The screen `derivation_candidates(table)` in the quality kit counts
   every triple of numeric columns that passes a structural prune. The
   prune is about cost: a product or sum whose operand magnitudes
   cannot land within 30× of the target is skipped. No identity the
   function would accept is lost.
2. A row supports a triple when all three columns are filled. It
   violates the triple when the target misses the form by more than
   0.011 or by more than a millionth of itself.
3. `detect_derivations` applies the two thresholds, in its own SQL: an
   identity holds at `match_rate >= 0.95` over at least 20 supporting
   rows.
4. The agent confirms which candidates are real derivations rather
   than coincidence ([candidates and judgment](judge.md)).

## Limits

- At most 12 numeric columns per table. The result says `truncated`
  when the cap applied.
- Two forms only, `b * c` and `b + c`. Deeper compositions are checked
  through metric definitions.
- On small tables a coincidental identity can pass the thresholds. The
  agent's review is part of the method.
