# Dependency plan

How glossdb knows that a stored result is still valid, and who brings
it current.

## The architecture

**Demand-driven incremental computation**, as in Adapton (Hammer et
al., PLDI 2014) and the red-green algorithm of Salsa and rustc. In the
terms of "Build Systems à la Carte" (Mokhov, Mitchell, Peyton Jones,
ICFP 2018): verifying traces with early cutoff, over a dependency
graph that is kept.

| The model's term | In glossdb |
|---|---|
| Revision | the lake's snapshot id. The only version there is |
| Input | a row of the catalog: an annotation on an asset, a view's definition, a relationship, a declaration; and a table's data. It changed at the snapshot its row begins or ends at; a table at the snapshot of its last load |
| Derived value | a stored result of a function on a subject. It carries the snapshot it was computed at and the snapshot its value last changed at |
| Dependency | one edge per input or result a function read when it ran, recorded by the read functions |
| Check | a result is current when nothing it read changed after the snapshot it was verified at. Asked on demand, walked along its edges |
| Early cutoff | a result computed again with the same value keeps the snapshot its value changed at, so what read it stays current |
| The graph | the edges as rows of the catalog, read by SQL. Not kept in memory: the whole check takes 91 ms at 500,000 results as one query (spike) |

The core knows no add-on. A kit's functions and the things it lets
one ask for (a scenario, a plan) are tracked by this one mechanism,
declared by the kit as rows; nothing in the core names a kit.

What must not exist beside it: a second version of anything (a digest
of what a read returned, a counter, a fingerprint as a key); a lineage
or a check computed whole after a write; a result that holds what one
asks for alone.

## Where the code stands (branch `snapshot-version`, both repositories)

| Part | State |
|---|---|
| The snapshot is the version: a result stores the snapshot it read at and the snapshot its value changed at; `inputs` is one row per node read; no digest | built (step 1). The nodes: the extension's `docs/specification/tables/inputs.md` |
| A write of what the catalog holds writes nothing: an annotation, a kit's macro or view, a replace load of the same columns | built |
| The check asked on demand: `glossql_outdated()` checks every result, a result's current mark checks that result and what it read; nothing kept | built (step 2, first half) |
| The reads kept per snapshot: `glossql_cached` (the glossary's values, tests, collapsed and raw reads), `glossql_kept` (`view_tests`, `view_summary`, `view_rows`), `glossql_kept_view`, the views' lineage per catalog version | stands against the model: computed whole after each write |
| A scenario, the range tolerance: annotations on the dataset; `metric_scenario` holds every scenario of a metric | stands against the model (#246) |

## Steps, in order

| # | Element | Risk | What it touches | State |
|---|---|---|---|---|
| 1 | The snapshot is the version | High | the extension, `SPEC.md` §6 | built |
| 2a | The check on demand, the kept check gone | Medium | the extension's store | built |
| 2b | A test's result and a view's lineage are stored results with the nodes they read, brought current like any result; the kept reads go | High: `SPEC.md` §5.3 and §7 say a detector runs at read | the extension (store, lineage), `kits/views`, `kits/goals` | open: put to the project lead, then a standalone spike |
| 3 | What one asks for alone is a node, declared by the kit that brings it: a scenario as a plan is; `metric_scenario` runs on a scenario. The core offers the declaration and names no kit | Medium: `SPEC.md` §4 and §6 | the lineage kit, `kits/outlook` | design page against the code first |
| 4 | A reader of an out-of-date result is "possibly out of date": served marked, and in `next` once the result it read is computed again and differs | Low | the extension's check, `kits/goals` | next |
| 5 | An interrupt during a computation; the Postgres catalog's lost-race path | Low | the extension | #247 |

## Left out of these steps, by the project lead

Built first without them; their form is settled once the rest runs.

- **Removing a function or a macro.** A declaration no kit brings any
  more is left as it is. Direction: a removal is soft (the row ends,
  nothing is deleted), and the results computed with it are retired.
- **Compaction and expiry.** Nothing is compacted or expired. Direction:
  only what no result references and no audit needs, or an archive:
  rows that are plainly out of date move out monthly or quarterly.

## Measured

| Workspace | What | Before step 1 | Now |
|---|---|---|---|
| Formula 1 (34 results) | a write that computes nothing | 0.24 s | 0.21 s |
| Formula 1 | a table view over three tables | 1.9 s | 1.23 s |
| `big` (200 tables, 300 views, 5,000 results) | a write that computes nothing | 0.39 s (step 1) | 0.30 s |
| `big` | `glossql_outdated()`, nothing kept | 128 ms (step 1) | 16 to 20 ms |
| `big` | `results_due()` after a write | 499 ms (step 1) | 355 ms, 224 ms of it `view_tests` and `view_summary` computed whole |
| `big` | a view definition | 2.23 s (step 1) | 1.66 s |

`big` is generated by `gen/gen.py` in the session's scratchpad (about
20 minutes); it moves into the repository with step 2b's spike.

## Done when, measured on the running server

- One version: no digest, counter or fingerprint decides whether a
  result is current. Done.
- An annotation on one metric, a relationship declared after a view's
  check ran: only what read the changed node is out of date, and
  `glossql_outdated()` names the node. Done.
- Declaring a scenario leaves the other scenarios' results current
  (step 3).
- On `big`, a write that computes nothing reads no dataset-wide result
  again (step 2b).

## How this plan is worked

A step replaces a structure, so its branch may be red until the step
is whole; the suites hold at merge. The tests of what a step deletes
are deleted first. `SPEC.md` is edited with the work; `grammar.ebnf`
needs the project lead's approval first. A change that departs from
the architecture above stops and is put to the project lead. This file
keeps the architecture section through every rewrite.

## Next issue (draft)

**Step 4, possibly out of date.** What it buys: a forecast, ranges, a
scenario or a plan whose input result is out of date is still served,
marked, and asks for an actor only when that input was computed again
and differs. What is there: the reason `outdated` in the check
(`CheckRowsSQL`, the extension's `glossql_store.cpp`), `results_due()`
and `next` in `kits/goals/kit.sql`. Done when: `glossql_outdated()`
names such a result `possibly`; `next` lists it only after the result
it read changed; both suites pass.
