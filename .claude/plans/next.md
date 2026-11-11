# Next plan

`next` becomes the work list of the data intelligence layer: what is
open on the bound dataset, by step (connect, describe, test, decide,
serve), derived from the states the catalog already holds and walked
along the lineage of the metrics. It is context: an ordered list with
the statement for each row. The calling agent decides. It serves two
situations with one read: building the layer (properties missing,
tests not run) and running it (a load changed the data: descriptions
outdated, a test turned red, a value outside its expected range).

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| `next`, the generic read: one row per asset and state, by step, in the order of priority | Low: measured on the employees data | `kits/goals/kit.sql`, its suite | Built | |
| What changed, per row: an outdated description and a test that is not green carry the cause: the newest load's row count against the load before, and the columns whose profile moved (distinct values, share empty, lowest, highest) | Low: measured on the employees data | `kits/goals/kit.sql`, `routes.rs` | Built | |
| The server runs the measurements its tests read: a profile of every column a metric reads and the relationship check, after a definition, an annotation or a load, a declared load included | Low | `built_in_tests` in `crates/duck/src/lib.rs` | Built | |
| A test brings its advice: each built-in check returns `finding` and `fix` in its result, and `next` serves them, so a kit that adds a test adds no branch elsewhere | Low: no change to the language | `kits/views/kit.sql`, `kits/goals/kit.sql`, `routes.rs` | Built | |
| The preview features' findings as rows: a value outside its expected range, a plan outside the forecast's range, a plan not compared, a plan without a definition (`outlook_findings()`); running the range and forecast measurements again moves at the switch | Low | `kits/outlook/kit.sql`, its suite | Built | |
| The switch: `next` is the new read; the hand-written blocks per kit and their composition at open are deleted; every result ends with the count per step and the first open row; `next://<dataset>/<step>`; docs and skills say so | Medium: every `next` test and the skills' text changed | `crates/duck/src/lib.rs`, `crates/serverd/src/window.rs`, `mcp.rs`, `routes.rs`, the kits' suites, `docs/extending/next-steps.md`, the skills | Built | |
| glossval reads the new `next` | Medium | `evaluation.md` has the rows | With the evaluation | |
| The wording the extension still serves in acknowledgements | Low | `harness.md`, loose ends | Before the pull requests | |

## What is there

- The glossary holds a state per asset and property: `missing`,
  `stale`, `conflict`, `current`. `view_tests()` holds each test's
  state and whether its result is current. `open_questions` and
  `review_decisions` hold what waits for a person and what a person
  decided. `imports` holds every load with its row count.
  `glossql_views_scans()` gives the tables and columns each metric
  reads.
- `next` is a view in the goals kit over these states. The line after
  each call and the `next://` page are rendered from its rows in
  `crates/serverd/src/window.rs`.
- Measured on the employees data (three tables, 331,603 rows, two
  metrics): the glossary holds 57 missing entries; the lineage of the
  two metrics narrows them to 23, in six rows. After a changed load of
  one table, the read reports the two descriptions on the changed
  column as outdated and the tests whose results predate the load.

- A description is outdated when its column's type or its derivation
  in the load query changed (SPEC §5.2). A load of the same shape
  with other values does not make it outdated. What such a load
  changed is the cause on a row that is open for another reason: a
  test that turned red, an expected range that was left.

## Tests

A test on `next` checks the step, the asset and the state of a row.
It compares text only for the statement a row hands the agent.
