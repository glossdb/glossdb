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
| The extension's changes of this round (`96b34b7` to `d05f951`) are tested, not reviewed line by line; glossval's goldens are not run against them | Medium | the extension; `../glossval` | Next | |
| The outlook kit: the forecast is one result for all metrics of a dataset, so a new metric makes it and every plan due; a response of the model service is not kept under a hash of the request; a `metric_scenario` run takes 2.3 s (1.8 s before); newest-row windows are left in the kit and the console's frames | Medium | `kits/outlook/kit.sql`, `kits/views/kit.sql` (`view_axes_of`), the extension's service call, `crates/apps/builtin/console/frames` | With the outlook issue (`harness.md`) | |
| A body that reads past the read functions is not refused: its result has an input `unnamed` and is outdated once stored. A suite test holds our bodies | Low while every function is ours | the extension (`BodyReads`) | When a customer writes functions | |
| Finer than needed today: lineage per output column of a view (from the SQL as JSON); an identical reload moves the table's version, so results are computed once more; an outdated result or annotation no view needs is listed nowhere | Low | the lineage kit, the extension (`glossql_runner.cpp`), `kits/goals/kit.sql` (`next`) | When one is measured as a cost | |

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
- **`results_due()`** is in `kits/goals/kit.sql`. **The server**
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

Server at `9962a9f`: 115 tests pass. Extension at `03cc58e`: its SQL
suite passes with 2787 assertions, lint clean. On the server on
127.0.0.1:8080 with the Formula 1 data (9 tables, 4 metrics), each
write one MCP call:

| Write | Before any lineage | With the read functions |
|---|---|---|
| `meaning` on a column no metric scans | 1.00 s, 4 results computed | 0.67 s, 0 |
| `meaning` on a table two metrics scan | 1.00 s, 4 | 0.67 s, 0 |
| `role` on a source column of a metric | 1.17 s, 4 | 0.68 s, 0 |
| `role` on a column a metric serves | not measured | 1.09 s, 1 |
| The same annotation again; a new property declared | not measured | 0.67 s, 0 |
| A relationship declared between tables no metric joins | 3.2 s, 12 (with the C++ lineage) | 0.67 s, 0 |

Per call, reported by the build and not repeated here:
`results_due()` 0.10 s, `next` 0.34 s, the currency check over 23
results and 89 inputs 0.06 to 0.07 s. On the goals fixture: with two
plans stored, a change to one leaves the other current; an unrelated
annotation, an added assumption and a declared plan leave the
dataset's preview measurements current.

## Next issue (draft)

**Review of the extension's dependency changes.** What it buys: the
branch can go up as one pull request whose diff a person has read.
What is there: the commits `96b34b7..d05f951` in the extension
(`src/glossql_runner.cpp`, `src/glossql_store.cpp`,
`kits/lineage/kit.sql`, `SPEC.md` §6, `test/sql/glossql_inputs.test`);
glossval's goldens (`../glossval/goldens`). Done when: the diff is
read line by line with findings fixed or listed; the goldens run
against this build with the same results as their baseline.
