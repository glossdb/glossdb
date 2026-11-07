# Relationship discovery

`detect_relationships` returns every plausible join between the loaded
tables, with cardinality, overlap, match and orphan counts, and the
distinct count on each side. It runs on a dataset
(`SELECT detect_relationships() FROM fin`). It is the first step of
three: this measurement proposes, the agent declares, and
[coherence](coherence.md) watches what was declared.

## What it answers

"Do this column's values live inside that one?" The question has a
direction, and its statistic is containment: the matched values over
the source column's distinct count. A small child key set fully inside
a large parent set scores perfectly, whatever the difference in size,
and that is exactly the shape of a real foreign key.

## How it works

1. **Cells.** The screen `relationship_candidates(dataset)` in the
   quality kit reads every cell of every table as `(table, column,
   type, row, value)`, joins the distinct values of two columns on the
   value within one stored type, and counts per column pair: the
   containment numerator, and each column's distinct count. Values
   compare as stored; nothing is cast.
2. **Key-like targets.** A target is key-like when nine in ten of its
   filled rows are distinct and it has at least two values.
3. **The floor.** A pair is admitted when at least half the source's
   distinct values appear in the target. This is the only floor in the
   screen, and it bounds output; it judges nothing.
4. **Composite keys.** Where the multi-tenant shape suggests them, the
   screen tries two-column keys: for each overlapping pair whose target
   is not a key alone, the same two tables are tried with a scoping
   column, in overlap order.
   - A scoping column that is unique on its own is never tried: the
     pair could identify no more than that column's own candidate
     already does.
   - Two tables that a key-like single pair already joins are not
     tried: a scope could only re-key a pair that has a key.
   - The pass first counts every combination's distinct pairs, an
     aggregate with no join, and settles the key test from those
     counts. Only the surviving source combinations are then joined to
     the surviving target combinations. A composite that passes the
     floor is returned with `key_columns` (the tuple is the key).
5. **Ranking.** Candidates rank by what a reference looks like, in this
   order:
   1. its target is a clean key: exactly unique in its table, and not a
      Date or Timestamp;
   2. it repeats: many-to-one before one-to-one;
   3. it resolves: overlap;
   4. it reaches its key: matched values over the key's distinct count.

   The clean-key tier comes first because a copied date column and a
   sibling table's own foreign key both contain a reference's values
   without being what it refers to, and a one-to-one overlap of 1.0 is
   as often two parallel surrogate sequences as a relationship. Overlap
   comes before coverage because a large surrogate id range covers a
   smaller one entirely while a fifth of its values resolve nowhere,
   and that decoy outnumbers a small code set sitting inside a dense id
   space at overlap 1.0. The code set ranks above a relationship with
   orphans and below one without, and the agent removes it against the
   data. The order demotes; it never drops.
6. **The result.** `detect_relationships` shapes and summarises the
   screen's rows and filters nothing beyond the floor.

The agent's review is half the method. Value containment cannot see a
key spelled differently on each side, and cannot reject a coincidence
shaped like a lookup. A reader with context declares the first and
prunes the second ([candidates and judgment](judge.md)).

## Scale

No column's values leave the engine: the screen is one query, and its
joins and aggregates spill to disk under the engine's memory limit.
The cost is fan-out: a value carried by many columns of one type meets
itself once per column pair. The composite pass limits that to the
pairs it was asked about.

## Limits

- Containment cannot see a join whose two sides share no values
  (surrogate-to-natural mappings). Those come in as declarations.
- A contained column is not necessarily a key. Coincidences shaped
  like a lookup pass the floor, and the agent removes them.
- Composite keys are tried two columns wide only: a scoping column
  beside the overlapping pair.
- Pairs inside one table are enumerated quadratically, which limits
  very wide tables. Load queries that load only the needed columns
  avoid it.
