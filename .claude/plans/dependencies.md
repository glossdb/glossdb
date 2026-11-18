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
| The snapshot is the version: a result stores the snapshot it read at and the snapshot its value changed at; `inputs` is one row per node read (the extension's `docs/specification/tables/inputs.md`); a write of what the catalog holds writes nothing | built |
| The check on demand (`glossql_outdated()`); a reader of an out-of-date result is `possibly` | built |
| A function's result, a test's result (per subject and test) and a view's lineage are stored results with an id, their inputs and their edges, brought current by the server after a write. Nothing is kept per snapshot, in the extension or in the server | built |
| A function declared on columns alone, called on a table or view, computes each column in one write (`completeness_check` per served column) | built |
| A load whose columns differ alters the table in place; an annotation is stale by the snapshot rule | built |
| One second connection per statement; a result's inputs and the current check are one query over all due subjects; the empty confirming round after a write is skipped | built |
| The suites: tests of replaced structures, hand-run test statements, text comparisons and duplicates across layers are deleted; the kit runner brings results current after a write as the server does | cut |
| Offloaded at the tag `before-cut` (both repositories): the `plan` and `outlook` kits, review by MCP elicitation, `workspace_status`, the `definitions` registry, `branch_rows` | gone from the branch |

## What still has the old shape, largest first

| # | Element | Risk | What it touches | State |
|---|---|---|---|---|
| 1 | `dataset_cells`: every cell unpivoted to text, pivoted back by each caller (1.8 s for 1M rows by 5 columns). To be a typed read of the view by name, first for a metric's series and the reconciliation | High | the extension, `kits/views`, `kits/harmonise`, the quality kit | spike first |
| 2 | The console frames: nine compute the whole dataset's series and filter to one view, so one metric without additivity refuses the page of every metric (422); the person-over-agent collapse repeated in 14. To read one view's series | Medium | `crates/apps`, `kits/views` | after 1 |
| 3 | The metric series is not stored. Spiked: stored rows read in 10 ms, but every load then computes every grain of every metric it feeds (11 s for 12 metrics on 1.3M rows) and keeps megabytes per version. Measured again after 1 and 2; taken up only if a read is still in seconds | Low | `kits/views` | after 2 |
| 4 | The stored lineage as one JSON value unnested into the columns of deleted functions (`views_*`). To be rows | Medium | the lineage kit | open |
| 5 | Review and summary logic in Rust that repeats kit reads; statement splitting and classifying in the server | Medium | `crates/serverd`, `crates/duck` | open |
| 6 | Three parse-tree walkers beside the bound-plan walk in the extension | Medium | the extension | spike first |
| 7 | The numeric evidence (stock and flow evidence, the discovery screens): stays where it is, in the extension's quality kit on text cells, while the code under it stays C++. Rust on Arrow was spiked and does not pay for these | Low | the quality kit | nothing to do |
| 8 | An interrupt during a computation; the Postgres catalog's lost-race path | Low | the extension | #247 |

## Left out, by the project lead

- **Removing a function or a macro.** Direction: a removal is soft, and
  the results computed with it are retired.
- **Compaction and expiry.** Direction: only what no result references
  and no audit needs, or an archive, monthly or quarterly.
- **Kit code outside the lake.** Spiked: the catalog reload after a
  write drops by about 60%, plan time does not change, and a reader of
  the lake alone loses `next`. The kit code stays in the lake. Whether
  the reload after a write is a caching question in DuckLake is not
  explored.

## Measured (Formula 1, one MCP call, by the session on its own server)

| What | Start of the round | Before the cut | Now |
|---|---|---|---|
| a write that computes nothing | 0.24 s | 0.28 s | 0.27 s: one `results_due()` round (87 ms) and `next` (127 ms), mostly planning the kit SQL |
| a table view over three tables | 1.9 s (10 results) | 2.6 s (28 results) | 1.12 s (28 results); 132 connections and 90 lake transactions, from 513 and 446 |
| the setup that defines the metrics | | 5.9 s | 2.97 s |
| the same annotation again | | 0.04 s, `next` kept | 0.17 s, `next` read on each call |

One view's console frames on this build: 0.13 to 0.20 s on Formula 1,
0.64 to 1.4 s on 200 metrics over 200 tables, 1.0 to 1.9 s on 12
metrics over 1.3M rows.

## How this plan is worked

The tests of what a step changes are deleted first, as a commit of
their own, so nothing is built towards them. Done-when is the flow
walked on a running server through MCP: load, describe, define a view,
read `next`, run the handed statements. New tests come last and few. A
new structure is spiked standalone first. `SPEC.md` is edited with the
work; `grammar.ebnf` needs the project lead's approval first. A change
that departs from the architecture above stops and is put to the
project lead. This file keeps the architecture section through every
rewrite.

## Next issue (draft)

**A typed read of a view's data for the kits.** What it buys: a
metric's series, the reconciliation and the profile aggregate typed
columns in the engine; the text unpivot and each caller's pivot back
go. What is there: `DatasetCellsBindReplace` in the extension's
`glossql_runner.cpp`; its callers in `kits/views/kit.sql` (three),
`kits/harmonise/kit.sql` (four) and the extension's quality kit
(four, the discovery screens, which read across columns of any type).
Done when, walked on a running server: a view's page and the
reconciliation read through the typed read, the callers it replaces
and their modes of `dataset_cells` are deleted, and one view's frames
on 1.3M rows answer in well under a second.
