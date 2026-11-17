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
| A view's lineage is a stored result, `lineage` on the view: stored in the write that defines it, with the nodes its planning read and its `reads` edges (`edges`); out of date like any result and computed first by `results_due()`; the lineage, the places, `place_nodes` and `definition()` read those rows, a place walked over a view records its `result lineage` | built (step 2b, lineage half). Kept per catalog version, and the view's rows kept per snapshot, are gone |
| A result has an id of its own (`measurements.id`), which its `inputs` and `edges` rows carry: one write may store several results | built (step 2b, test half) |
| A test's result is a stored result per (subject, test): `SELECT <test>() FROM <subject>` computes, in one write, each subject at or under the subject that holds a value of the test's property where the stored result is missing or not current, with the nodes it read (the subject's `annotation` and `value` of the property, its `definition`, `property`, the detector's `function`), and retires the results on subjects that hold none; `results_due()` lists it at ord 3 and the server runs one statement per test | built (step 2b, test half) |
| A detector that compares the subjects it runs over is refused at `DECLARE TEST` (`cross_subject`): a window not partitioned by subject, an aggregate over the values not grouped by subject, a join of two reads of the values not matched on subject. No shipped test is cross-subject | built |
| `GLOSSARY()` and `TESTS()` read stored rows; each read's rows are computed on the second connection when the statement runs, once per statement, the marks planned there; `view_summary()` and `view_tests()` are reads; `glossql_cached` and `glossql_kept` are gone | built (step 2b, test half) |
| An annotation is stale once its subject's `definition` node changed after it was written: a table column's own rows, a view column's view row, a table's or a view's definition. A load whose columns differ makes the table again, so every annotation on it reads stale; a type changed and changed back stays stale | built; the old rule compared types and loads |
| A kit's place: planned per read from the kit's macro over edges read from annotations (116 plans of `its metrics` in one scenario estimate) | stands: storing it means storing the kit's edges |
| A scenario is an asset of the outlook kit's own kind and its estimate runs on it; the range tolerance is annotated on the metric; the plan kit declares the plan's edge and place | built (step 3) |
| A reader of an out-of-date result is `possibly`: served marked, in `next` only once the result it read changed | built (step 4) |

## Steps, in order

| # | Element | Risk | What it touches | State |
|---|---|---|---|---|
| 1 | The snapshot is the version | High | the extension, `SPEC.md` §6 | built |
| 2a | The check on demand, the kept check gone | Medium | the extension's store | built |
| 2b | A test's result and a view's lineage are stored results with the nodes they read, brought current like any result; the kept reads go | High: `SPEC.md` §5.3 and §7 said a detector runs at read | the extension (store, lineage), `kits/views`, `kits/goals` | built. A test is treated like a function; a detector that compares the subjects it runs over is refused at `DECLARE TEST` and declared on the containing asset (spike `spikes/stored-tests-and-lineage`) |
| 3 | What one asks for alone is a node, declared by the kit that brings it: a scenario as a plan is; `metric_scenario` runs on a scenario. The core offers the declaration and names no kit | Medium: `SPEC.md` §4 and §6 | the lineage kit, `kits/outlook`, `kits/plan` | built |
| 4 | A reader of an out-of-date result is "possibly out of date": served marked, and in `next` once the result it read is computed again and differs | Low | the extension's check, `kits/goals` | built |
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
| Formula 1 (34 results) | a write that computes nothing | 0.24 s | 0.21 s; 0.23 s with the lineage stored; 0.31 s with the tests' results stored and the reads kept by none |
| Formula 1 | a table view over three tables | 1.9 s | 1.23 s; 1.43 s with the lineage stored; 1.75 s with the tests' results stored (13 results, 2 of them tests') |
| Formula 1 | the same annotation again | | 0.08 s with the lineage stored; 0.15 s with the tests' results stored |
| `big` (200 tables, 300 views, 5,000 results) | a write that computes nothing | 0.39 s (step 1) | 0.30 s; 0.31 s with the lineage stored (300 of the 5,000 results are lineages); 0.36 s with the tests' results stored (1,621 of 5,042), no result stored and one snapshot per write |
| `big` | `glossql_outdated()`, nothing kept | 128 ms (step 1) | 16 to 20 ms; 18 ms with the tests' results stored |
| `big` | `results_due()` after a write | 499 ms (step 1) | 355 ms (step 2a); 289 ms with the lineage stored, `view_tests` and `view_summary` still computed whole; DuckDB shell, the first read after a write: 182 ms with the lineage stored, 138 ms with the tests' results stored; read again at the same snapshot 45 ms kept, 128 ms not |
| `big` | `GLOSSARY(big)` after a write, through MCP | | 0.02 s kept per snapshot; 0.06 s read from stored rows (DuckDB shell: 3 ms kept, 39 ms) |
| `big` | `next`, the first read after a write (DuckDB shell) | | 199 ms kept; 170 ms not |
| `big` | a view's console page (`views?view=v010`), its 7 frames, the first after a write / again | | 15.1 s / 4.0 s kept; 15.3 s / 4.0 s not. The metric's trend frame is 13.6 s of it, before and after |
| `big` | the dataset's console page, its 3 frames | | 0.23 s kept; 0.51 s not |
| `big` | a load that adds a column to a table four views read | | 3.3 s: four lineages computed again with the same value, none out of date after |
| `big` | a view definition | 2.23 s (step 1) | 1.66 s; 1.61 s with its lineage stored in the same write (1.35 to 1.41 s on the same run as below); 1.86 s with the tests' results stored |
| `big` | `lineage('big')`, whole / the first read after a view definition | 17 ms / 252 ms (step 2a) | 4 ms / 106 ms, about 80 ms of it the first read of any kind after a write |
| outlook suite replayed | a computed scenario estimate, per MCP call / its body | 4.0 s / 3.4 s (step 2a) | 3.76 s / 3.35 s |
| the server's kit suite | `the_kits_suites_pass` | 45 to 48 s (step 2a) | 40 s; 52.5 s with the tests run before each read of their results |

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
  again (step 2b). Done: after such a write `results_due()` lists
  nothing, no result is stored and the write takes its own snapshot
  alone; no detector runs. The reads still mark the stored rows of
  the dataset, once per statement.

## How this plan is worked

A step replaces a structure, so its branch may be red until the step
is whole; the suites hold at merge. The tests of what a step deletes
are deleted first. `SPEC.md` is edited with the work; `grammar.ebnf`
needs the project lead's approval first. A change that departs from
the architecture above stops and is put to the project lead. This file
keeps the architecture section through every rewrite.

## Next issue (draft)

**A read's marks cost each statement.** What it buys: a read of the
glossary, a view's tests or `next` at the same snapshot costs what the
first read after a write costs. What is there: the marks are planned
and run on the second connection per read (`glossql_store.cpp`,
`ReadInit`), once per statement; `GLOSSARY(big)` 39 ms against 3 ms
kept, `view_tests()` 66 ms against 15 ms, measured. Most of it is
planning the check's union of node kinds (`NodeChangesSQL`), not
running it. Done when: the check plans the node kinds the results in
scope read alone, and a read at the same snapshot is measured again on
`big`; nothing is kept between statements.
