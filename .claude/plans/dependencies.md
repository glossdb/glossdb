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
| The graph | nodes and edges kept in memory per instance, built from the catalog when the lake opens, updated by each write |

What must not exist beside it: a second version of anything (a digest
of what a read returned, a counter, a fingerprint as a key); a lineage
or a check computed whole after a write; a result that holds what one
asks for alone.

## Where the code stands against it

| Part | Today | Against the model |
|---|---|---|
| Catalog rows carry `begin_snapshot` and `end_snapshot`; a write takes the lake's next snapshot id | built | it is the model's revision |
| The read functions record what a body reads | built | the edges, but stored per read, not per node read |
| `inputs.version`: a digest of what each read returned, compared again for every result at every snapshot | built | a second versioning system beside the snapshots. It goes |
| The lineage: a SQL macro over the catalog, evaluated at each call | built | no graph is kept. It goes |
| The out-of-date check, whole per snapshot, then cached (`glossql_kept`, the kept check) | built | the cache around the missing graph. It goes |
| A scenario, the range tolerance: annotations on the dataset; `metric_scenario` per metric, `metric_ranges` per dataset | built | not nodes; one change puts all of it out of date (#246) |

Size today: the extension's `src/` 9,851 lines, the kits' SQL 5,704.
Each step below ends with both counted again, and smaller.

## Steps, in order

| # | Element | Risk | What it touches | Deleted in the same step |
|---|---|---|---|---|
| 1 | The snapshot is the version. An input row names the node read (asset and what) and no digest. A result is out of date when a node it read has a catalog row begun or ended after the result's snapshot, or a table loaded after it. A result computed again with the same value keeps its changed-at snapshot | High: every stored result and `SPEC.md` §6 | the extension (`inputs`, the runner), `SPEC.md` §6 | `inputs.version`, the digest of a read (`ReadsNowSQL`), its tests |
| 2 | The graph in memory: nodes with their snapshots, edges both ways, built at open and updated in the step of each write; another writer's snapshots are applied from the catalog's rows since. `lineage()`, the places, `glossql_outdated()` and the `current` mark are served from it | High: transactions, two writers, a Postgres catalog | the extension (store, runner, lineage kit) | the whole check per snapshot, the kept check, the lineage macro's joins, `glossql_kept` where the graph answers |
| 3 | What one asks for alone is a node: a scenario is an asset as a plan is, with edges to the levers it sets; `metric_scenario` runs on a scenario, `metric_ranges` on a metric | Medium: `SPEC.md` §4 and §6, shown to the project lead first | the lineage, `kits/outlook` | the per-dataset and per-metric result shapes |
| 4 | Pull features are verified when asked: a forecast, ranges, a scenario, a plan is served marked "possibly out of date" while a result it read is out of date, and enters `next` once that result is computed again and differs | Low after step 2 | `kits/goals` (`next`), the extension's `current` mark | the reason `outdated` |
| 5 | An interrupt during a computation; the Postgres catalog's lost-race path | Low | the extension | #247 |

## Done when, measured on the running server

- One version: no digest, counter or fingerprint is compared anywhere
  to decide whether a result is current.
- A generated workspace of 200 tables, 2,000 columns, 300 views and
  5,000 results: the graph's build time at open, its memory, and the
  time of a write that computes nothing. On Formula 1 that write is
  0.24 s today.
- Declaring a scenario, an annotation on one metric, a relationship
  declared after a view's check ran: only what read the changed node
  is out of date, and `glossql_outdated()` names the node.
- glossval's goldens are the same, or differ by the columns of
  `inputs` and `glossql_outdated()` alone.
- `src/` and the kits' SQL are smaller than the counts above.

## For the project lead to decide

- Whether a member of a dimension or a period is a node.
- Step 3's `SPEC.md` diff, before it is built.
- Whether the architecture section above goes into `CLAUDE.md`, so
  that every session starts from it.

## How this plan is worked

A step replaces a structure, so its branch may be red until the step
is whole; the suites hold at merge. The tests of what a step deletes
are deleted first. A change that departs from the architecture above
stops and is put to the project lead. This file keeps the architecture
section through every rewrite.

## Measured before

Formula 1 workspace, one MCP call each: a write that computes nothing
0.24 s (1.0 to 3.2 s before the read functions); a table view over
three tables 1.9 s. Per metric against a dataset's metrics in one
forecast request: no measurable difference on three datasets
(glossval `evals/README.md`).

## Next issue (draft)

**Step 1, the snapshot is the version.** What it buys: one versioning
system, and a check that is a comparison of two snapshot ids. What is
there: `begin_snapshot` and `end_snapshot` on every catalog row; the
lake's change log per table; `inputs` with one row per read and its
digest (`docs/specification/tables/inputs.md` in the extension);
`ReadsNowSQL`, `CheckRowsSQL`, `rc_outdated` in the runner and store.
Done when: `inputs` has one row per node read and no `version`; the
three cases above are out of date by snapshot alone; an annotation
changed and changed back reads as changed (it is a new snapshot); the
extension's suite and the server's pass; the line counts are in this
file.
