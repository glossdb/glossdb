# The plan

glossdb builds a company's data intelligence layer: connect, describe,
test, decide, serve. This file is the frame. It lists what is open,
first the data intelligence direction, then the backlog by step. The
plans beside it: `platform.md` (dbt, semantic models, lakes, the
workspace as code), `sources.md` (spreadsheets, documents, search),
`gate.md` (access per user), `clients.md` and `chat.md` (the hosted
trial), `evaluation.md` (what glossval measures), `next.md` (the
`next` rework and what is left of it).

## First: the data intelligence direction

Finished before anything new is picked.

| # | What | State |
|---|---|---|
| 1 | Text: `CLAUDE.md`, the prose skill, `README.md`, the docs overview, the extension's README | on the branch `data-intelligence` in both repositories |
| 2 | The extension's pages tell how a data harness works and why it is needed; glossdb's pages tell data intelligence | on the branch |
| 3 | What an agent reads on connecting (`INSTRUCTIONS` in `crates/serverd/src/mcp.rs`) and the opening of each skill name the job: building the layer | on the branch |
| 4 | `next` derived from the states the catalog already holds (missing, outdated, conflict, a red or not-run test, a decision waiting), walked along the lineage of what the person asked for: source, table, column, join, metric. An ordered list as context; the calling agent decides. One generic query and one text per state replace the hand-written blocks per kit. Tests on wording are changed or deleted on the way | built in the server (`next.md`); glossval reads it next |
| 4b | A decision model that ranks the steps: of interest only for small models; frontier models decide well from an ordered list | parked |
| 5 | The console: a second pass against the five questions (which sources map, what does this mean, can we trust it, who decides, where does it come from), with the issues the project lead found in the UI; its tests that pin labels are changed or deleted on the way | after 6 runs |
| 6 | glossval measures the layer: an agent builds it, a second agent reads the lake with plain DuckDB; real data first (`evaluation.md`) | next |
| 7 | Results page and websites | after 6 |

## The backlog, by step

| Step | Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|---|
| Connect | Harmonisation kit: the mapping of several systems of record onto one target model, and the reconciliation per load | Medium: the demo's statements are written for one case; the kit must hold for a second | `kits/`, a skill, a suite; the statements in `../glossdemo/statements/` (structure, harmonise, watch) and its Mapping and Reconciliation pages | The first use case | |
| Connect | Works with your platform: dbt, semantic models, lakes read in place, attached databases | See `platform.md` | | | #221 |
| Connect | Spreadsheets, documents, search | See `sources.md` | | When a customer brings the data | |
| Describe | The workspace as code: declarations as `.glossql` files, tested in CI | See `platform.md` | | | #219 |
| Describe | Citations to documents on tables, columns, relationships and metrics | Low | an optional kit | With documents | #220 |
| Test | A certification level per metric: the level sets which tests and which review a metric needs before it is served as certified | Low: a property and a read over `view_tests()` | the views kit, `next`, the console's metric page | After the harmonisation kit | |
| Test | A recompute rule: a measure that does not sum from its members is recomputed, not summed | Medium | the views kit | | #41 |
| Decide | Access per user | See `gate.md` | | When a workspace has a second user | |
| Decide | A recommendations read: findings with their options, chosen in the console (preview) | Low | the outlook kit, a console tile | | #174 |
| Decide | A review decision made inside the chat | See `chat.md` | | With the trial | #20 |
| Serve | The hosted trial | See `clients.md` | | | |

Housekeeping, outside the steps: #214 (the image hangs on opening a
seeded workspace), #60 (an infrastructure error's text reaches the
client), #56 (Tera 2 for the app pages).

## Loose ends of this round

Closed before the pull requests open, or moved to a row above.

| What | Where | When |
|---|---|---|
| The extension's description reads "the context language over DuckDB" | the extension | before the pull requests |
| The console's tests pin about 110 labels | `crates/apps/tests/suite/console.rs` | with row 5 |
| A workspace opened before the switch keeps a dead `next_steps` view and three `routes_*` macros | the demo workspace is rebuilt | with row 6 |
| A test's result reads as not current after a load of a table the metric does not read | `view_tests()`, the data version the extension stores for a result | after row 6 |
| One pull request per repository for the branch `data-intelligence` | both repositories, glossval on its own | when rows 1 to 6 are done |

## Measured

On `hr` (two metrics, 331,603 and 443,308 rows), per MCP call: any
statement 0.4 s, of which `next` is 0.33 s; a definition with its
tests 2.5 s; an annotation on a scanned table 1.8 s.

CI: the server 4 to 6 minutes; the extension 6 minutes per platform, a
pull request builds linux_amd64 alone. The server's CI waits for the
extension's build of the pinned commit before building it itself.

## Rules learned

- A red test alone is a failed test, not a conflict.
- A check that reads other functions' results re-runs when those change.
- A test with nothing to check is green with the reason, not a chore.
- A workspace made before a catalog column was added is rebuilt.
