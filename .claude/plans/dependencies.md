# Dependency plan

How glossdb knows that a stored result is still valid, and who brings
it current. It works as a build system does. The model is `model.md`,
agreed with the project lead, and it is built:

1. **A function's body says what it reads**, through three read
   functions whose arguments are a what and a where on the lineage:
   `annotations(property, where)`, `results(function, where)`,
   `definition(where)`. The reads are taken from the body as written
   (its JSON) when the function is declared, and stored with it
   (`functions.reads`).
2. **A stored result keeps what those reads returned**: one `inputs`
   row per read, with a digest; for data, DuckLake's version of each
   table and view read.
3. **A result is current while each read returns the same**, and no
   result it read is outdated. Otherwise it is outdated: served and
   marked. `glossql_outdated()` names the read that differs.
4. **One read says what is due**: `results_due()` lists the results a
   dataset's views want that are missing or outdated, with the
   statement that computes each, an input before what reads it.
5. **Two readers of that one read.** The server runs it after a
   write, until nothing is left. `next` lists what the server leaves:
   what only an actor can do (a statement to write, a red test, a
   decision, a preview measurement that is due, since those call the
   model service in `../glossthesi` and an actor starts them).

A result no view wants is not due. Nothing else decides what is
computed: no second list, no flag.

## Open, in risk order

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| A write that computes nothing takes 0.56 s, a read 0.02 s. The write itself is 0.001 s; the rest is DuckDB planning the kits' SQL: `next` for the closing line 0.32 to 0.35 s (about 80% planning, the outlook kit's branches planned though no model service is named), `results_due()` 0.18 to 0.23 s | Low: known, and paid once per write | `kits/goals/kit.sql`, `kits/outlook/kit.sql` | When it hurts an agent's run | |
| Where "metric" still stands for "view": `view_summary()` fills `missing` and `columns_without_role` on a table view though `next` asks for them only under describe; its column `metric` and the `metric_reads` read cover every view; the console's empty state on the views page and one line of `docs/usage/test.md` say metrics | Low | `kits/views/kit.sql`, `kits/goals/kit.sql`, `crates/apps/builtin/console`, `docs/usage/test.md` | With the harmonisation kit (`harness.md`) | |
| Left from the review of the extension's changes: the write path's lost-race and interrupt handling is read, not run (no second writer, no Postgres catalog in the suites); glossval has no accepted goldens baseline at these commits | Medium | the extension (`glossql_store.cpp`, `glossql_runner.cpp`); `../glossval/goldens` | Before the pull requests | |
| `next` has no level: every open row is a must, and it names the outlook kit's reads. A row keeps its kind of work (integrate, describe, test, review) and gets a level: must (served data is wrong or cannot be served), should (the layer is incomplete for what is served), could (what sits on top or beside). A kit adds rows through its own tests; later a kit's configuration says how it enters `next` | Medium: it changes what an agent is told | `kits/goals/kit.sql`, `crates/serverd/src/window.rs`, `crates/serverd/src/mcp.rs`, the skills | After the rows in work | |
| The outlook kit is a pull-in: nothing stored, nothing asked. Of its 1,557 lines 62 repeat what the model service decides, 141 could move there, about 270 are glue for `next` and `view_tests()`, 120 are its own count of how often ranges held. It disagrees with the service on the scenario history gate and the per-metric range state, serves an older forecast when the newest run failed, and puts the forecast model's coverage on scenario ranges. One forecast per metric; the newest-row windows go. Plan against actual (about 330 lines, no model needed but for the forecast column) becomes a kit of its own | Medium | `kits/outlook/kit.sql`, a new `kits/plan`, `../glossthesi` (a state per metric, a code per error: in work there) | After `next` | |
| A body that reads past the read functions is not refused: its result has an input `unnamed` and is outdated once stored. A suite test holds our bodies | Low while every function is ours | the extension (`BodyReads`) | When a customer writes functions | |
| An identical reload moves the table's version, so results are computed once more | Low | the extension (`glossql_runner.cpp`) | In work: built if the comparison is cheap, else dropped with the number |

## What is built

- **One write, one transaction** (`Inner::Write`). A catalog write
  takes the lake's next snapshot id with its rows. A new row ends the
  row it replaces (`end_snapshot`); no row is deleted. `<name>` serves
  the current rows, `<name>_history` every row. A write is tried again
  only when another writer took its snapshot id.
- **The lineage as one relation**, `lineage(dataset)`, in the
  extension's lineage kit: what a dataset contains, what a view reads
  and joins on, a relationship's two columns, the metric a plan plans.
  The places a read names are walked over it: itself, its columns,
  its sources, the columns it joins on, its relationships, its
  metric, its dataset, the dataset's metrics, the dataset.
- **Every shipped body reads through the read functions.** A test in
  each suite holds them to it, with no exception. `join_check` is the
  one check of a join that repeats rows. `relationship_coherence`
  stores one result per relationship.
- **Inputs are the reads**, written with the result. One SQL
  definition computes a read's digest when the result is stored and
  when it is checked.
- **A computation that fails is a result**: stored with its inputs
  and its error, current. A direct call computes it again.
- **Snapshot expiry**: an annotation whose earlier catalog row is
  gone reads as outdated. A load in place of a table with the same
  columns leaves every result current.
- **`results_due()`** is in `kits/goals/kit.sql`. It starts from every
  view that is defined and not stopped (metric, table view, single
  value) and wants the checks behind its tests and, before them, the
  results those checks read, taken from the checks' stored reads. **The server**
  (`bring_current` in `crates/duck/src/lib.rs`) runs it after a
  write, in rounds, before the next read of the same call. **`next`**
  reads the catalog's states and `load_changes()`.
- **Gone**: the inputs derived from a body's bound plan, the lineage
  computed in C++ with its widenings, the filter on what a running
  function sees, `glossql_parts()`, the outlook kit's hand-made
  inputs digest, `forecast_exists`, `scenario_exists`,
  `fan_out_check` and `validity_check` as two, `open_items`, the
  console's re-measure button. `glossql_runner.cpp` went from 2947 to
  2401 lines in the last step.

## Measured

Server at `0017cc5`: 116 tests pass. Extension at `f5bdfca`: its SQL
suite passes with 2966 assertions, lint clean. The extension's
changes since `96b34b7` were reviewed line by line by two reviewers;
the confirmed findings are fixed, each with a test. glossval's series
capture equals each metric's own SQL (0 differing cells) and its
import path agrees with a fresh load. On the server on
127.0.0.1:8080 with the Formula 1 data (9 tables, 4 metrics, 1 table view), each
write one MCP call:

| Write | Before any lineage | With the read functions |
|---|---|---|
| `meaning` on a column no metric scans | 1.00 s, 4 results computed | 0.56 s, 0 |
| `meaning` on a table two metrics scan | 1.00 s, 4 | 0.56 s, 0 |
| `role` on a source column of a metric | 1.17 s, 4 | 0.56 s, 0 |
| `role` on a column a metric serves | not measured | 0.88 s, 1 |
| The same annotation again; a new property declared | not measured | 0.56 s, 0 |
| A relationship declared between tables no metric joins | 3.2 s, 12 (with the C++ lineage) | 0.56 s, 0 |
| A table view defined over three tables | not built | 2.12 s, 10: 7 column profiles, 1 relationship check, its join and orphan checks |
| A relationship declared that the table view joins over | not built | 0.99 s, 2: the relationship check and the view's orphan check |
| `meaning` on a column the table view reads | not built | 0.57 s, 0 |

Per call, reported by the build and not repeated here:
`results_due()` 0.10 s, `next` 0.34 s, the currency check over 23
results and 89 inputs 0.06 to 0.07 s. On the goals fixture: with two
plans stored, a change to one leaves the other current; an unrelated
annotation, an added assumption and a declared plan leave the
dataset's preview measurements current.

## Next issue (draft)

**`next` with levels.** What it buys: an agent knows what it must do
before a dataset can be served, what it should do, and what it could;
a kit such as the outlook kit is used when asked for and not a chore.
What is there: the `next` view and `results_due()` in
`kits/goals/kit.sql`, the tests' own `finding` and `fix`
(`view_tests()`), the closing lines of a call
(`crates/serverd/src/window.rs`), `outlook_findings()` and
`outlook_measurements()` named inside `next`. Done when: every row of
`next` carries its kind of work and a level; the closing line counts
must and should; work on a dataset is complete with no must open;
`next` names no kit; a server without the outlook kit serves the
same `next` for a dataset with no stored preview result.
