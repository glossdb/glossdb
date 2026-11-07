# Relationship coherence

`relationship_coherence` checks what each declared relationship claims
against the rows it covers today. It runs on a dataset
(`SELECT relationship_coherence() FROM fin`) and reports, per
relationship: fill, orphan count and rate, and per column pair the
share of child rows dated before their parent (`precedes_rate`).
[Discovery](discovery.md) proposes relationships, the agent declares
them, and this measurement watches them from then on.

## What it answers

Two faults that no single-column check can see:

- **Orphans, counted exactly.** A child key with no parent is what an
  invented or mispaired key leaves behind. An exact count catches what
  sampling misses, including one orphan value repeated many times,
  which defeats counting by rare categories. On a high-cardinality key,
  every single-column engine tested scored exactly 0.0 on these faults.
- **Dates out of order.** A child event dated before its parent exists
  is what a wrong pairing leaves even when the keys join. `precedes_rate`
  is evidence, not a result: a payment before its invoice's due date is
  ordinary, a payment before the invoice exists is a fault. The agent
  reads the column names and decides.

A composite relationship joins on every column of its key.

A relationship inside one table is one of two things, and the target
side tells which:

- **A self-reference.** When the target is unique over the table, it is
  a key (`accounts.parent_id -> accounts.account_id`), and the check is
  a join of the table with itself.
- **A nesting.** Otherwise it is recorded finer to coarser
  (`city -> country`). It asserts that every finer value determines one
  coarser value, and its orphans are the rows whose finer value maps to
  more than one.

Neither carries date evidence: a date pair between a table and itself
says nothing.

## How it works

The screen `relationship_checks(dataset)` in the quality kit computes
fill, orphans and date order per declared relationship, with each
side's rows pivoted onto the relationship's columns. The measurement,
`relationship_coherence`, shapes the result per relationship, with the
date evidence nested per column pair. There are no thresholds in the
path: rates are returned, and thresholds belong to tests and to the
agent.

## Limits

- Declared relationships only. An undeclared join is nobody's claim and
  is not watched.
- Date order needs date columns on both sides, up to three tried per
  side. Pairs without them give no date evidence.
- An orphan rate says a pairing is broken, not which side broke. The fix
  is a load query or a new declaration, and choosing is the agent's or a
  person's call.
