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
| `next_steps`, the generic read, beside today's `next` | Low: prototyped on the employees data | `kits/goals/kit.sql`, its suite | Built | |
| What changed, per row: an outdated description and a test that is not green carry the cause: the newest load's row count against the load before, and the columns whose profile moved (distinct values, share empty, lowest, highest) | Low: measured on the employees data | `kits/goals/kit.sql`, `routes.rs` | Built | |
| The server runs the measurements its tests read: a profile of every column a metric reads and the relationship check, after a definition, an annotation or a load, a declared load included | Low | `built_in_tests` in `crates/duck/src/lib.rs` | Built | |
| The fix advice per test moves from the hand-written blocks to the test's own declaration, so a kit that adds a test brings its advice | Medium: touches every built-in test; a declaration field may be the extension's | `kits/metrics/kit.sql`, `kits/outlook/kit.sql`, maybe SPEC | Next | |
| Expected ranges, forecast and plan findings as rows under test (preview) | Low | `kits/outlook/kit.sql` | After | |
| The switch: `next` is the new read; `routes_<kit>()` and their composition at open are deleted; the line after each call gives the count per step and the first open row | Medium: every `next` test and the skills' text change | `crates/duck/src/lib.rs` (`next_view`, `write_next`), `crates/serverd/src/window.rs`, `routes.rs`, the kits' suites, `docs/extending/next-steps.md`, the skills | Last | |
| glossval reads the new `next`; its finish line is an empty list for the agent | Low, outside this repository | glossval's `next_state.py` | With the switch | |

## What is there

- The glossary holds a state per asset and property: `missing`,
  `stale`, `conflict`, `current`. `metric_tests()` holds each test's
  state and whether its result is current. `open_questions` and
  `review_decisions` hold what waits for a person and what a person
  decided. `imports` holds every load with its row count.
  `glossql_views_scans()` gives the tables and columns each metric
  reads.
- Today's `next` is written at open from each kit's `routes_<kit>()`:
  SQL text with one hand-written branch per test and state. It covers
  tests and review. It does not cover sources, descriptions or what a
  load changed.
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
