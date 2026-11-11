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
| What changed, per row: the load that made a description outdated, with its row count against the load before; the profile before and after where one is stored | Medium: a profile is stored per data version, the comparison is new | `kits/goals/kit.sql`, the quality kit's profiles | Next | |
| The fix advice per test moves from the hand-written blocks to the test's own declaration, so a kit that adds a test brings its advice | Medium: touches every built-in test; a declaration field may be the extension's | `kits/metrics/kit.sql`, `kits/outlook/kit.sql`, maybe SPEC | After | |
| The server runs the measurements its own checks need | Low | `built_in_tests` in `crates/duck/src/lib.rs` | After | |
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

## Tests

A test on `next` checks the step, the asset and the state of a row.
It compares text only for the statement a row hands the agent.
