# Dependency plan

How glossdb decides that something is outdated, and when it computes
it again. Today this is one base rule with exceptions added case by
case. This plan replaces that with one concept, agreed before any
further code. Until then the topic is frozen: no new exception, no
new clause.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The facts: every rule in the code today, the grain of each dependency, what the engine can tell about what SQL reads, the cost of a read and a write on a release build | Low: reading and measuring | this file, "What is there" and "Measured" | In work | |
| The matrix: everything that can be outdated against everything that can change, with the grain in each cell, agreed with the project lead | Medium: the cells where the engine cannot see what was read decide the design | this file | Next | |
| One rule for validity and one for when to compute again, chosen from the matrix; what of today's code goes | High: it changes the extension's core read and the server's behaviour after a write | the extension (`src/glossql_store.cpp`, `SPEC.md` §5 and §6), `crates/duck/src/lib.rs`, the kits | After the matrix | |
| The change itself, in steps that each pass both suites | High | both repositories | After the rules | |

## The three questions

Every system of this kind answers three questions. They were answered
here one case at a time.

1. **What can change?** A load, a table's shape, a view's definition,
   an annotation, a relationship, a declaration, a stored result, a
   review decision.
2. **What can be outdated, on what does it depend, at which grain?**
   An annotation, a stored result of a function, a test result, a
   preview result, a row of `next`.
3. **When is it computed again?** After a write, at a read, once per
   call, or when someone asks.

## What is there

Established; the rest follows with the facts.

- **Data** is versioned per table by the lake's snapshots. A result
  that read a table is outdated after a load of that table. This part
  is precise.
- **The catalog** is versioned per whole relation. A result that read
  the glossary is outdated after any write to the glossary, by anyone,
  on anything.
- **Why catalog writes count at all:** the built-in checks compute
  from the catalog. `additivity_check` reads the additivity
  annotation; `orphan_check` reads the relationships and a stored
  result. A corrected annotation must make them run again.
- **Exceptions on top**, each added for one case: `*` and `**` in a
  result's reads; functions that read other functions' results;
  the declaration-newer rule; the outlook kit's own digest (deleted);
  `DEPENDS ON` (built, provisional).
- **What `DEPENDS ON` showed.** It is precise for the catalog. But a
  function whose reads the engine cannot list is taken to read every
  table of the dataset, so any load makes it outdated. The old digest
  was more precise there.
- **When things run again today.** After each catalog write the
  server runs about ten built-in checks before it answers. Test
  results are computed at each read. Preview results run when an
  agent asks.

## Measured

- Debug build, Formula 1 workspace (9 tables, 5 views): a read of
  `next` 0.9 s; an annotation 5 to 6 s, of which most is the built-in
  checks running again.
- Release build: to be measured.

## Prior art

- **Build systems** ("Build systems à la carte", Mokhov, Mitchell,
  Peyton Jones): a system is one choice of when to rebuild and one
  choice of how to know a result is valid. Ours is a verifying trace:
  each result stores the versions of what it read. The method is
  sound; the keys are too coarse for the catalog.
- **Incremental computation** (Salsa): the same trace with early
  cutoff: an input changed, an intermediate value did not, nothing
  downstream runs. `DEPENDS ON` is a hand-written early cutoff.
- **dbt, Dagster:** dependencies are declared; each asset has a data
  version and a code version.

## The open design question

How the system learns what a SQL body read from the catalog. Three
ways, and today's code mixes them:

- **Declared:** the author states it (`DEPENDS ON`, dbt's `ref`).
- **Discovered:** the engine sees it. Tables and columns can be read
  from a plan; which rows of a catalog table were read cannot, as far
  as known. `json_serialize_sql` is to be checked.
- **Approximated:** the whole relation counts (today's base rule).

## Next issue (draft)

**The dependency matrix.** What it buys: one agreed page that says,
for everything that can be outdated, what it depends on and at which
grain, so that the rule and the cost follow from it. What is there:
this file; the facts gathered for it. Done when: the matrix is filled
from the code, each cell that the engine cannot see is marked, the
release-build cost of a read and of a write is in "Measured", and the
project lead has chosen the rule for validity and the rule for when
to compute again.
