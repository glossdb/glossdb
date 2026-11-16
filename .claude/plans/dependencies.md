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
| A write that computes nothing takes 0.54 s, a read 0.02 s. It was 0.44 s before the harmonisation kit and has grown with each round that added rows to `next` (0.49, then 0.54). The write itself is 0.001 s; the rest is DuckDB planning `next` (0.31 s) and `results_due()` (about 0.2 s) | Medium: every write of an agent pays it | `kits/goals/kit.sql`, `kits/views/kit.sql` (`view_tests()`) | In work | |
| Not tested: an interrupt during a computation is not stored as a failed result (the server's interfaces expose no interrupt); the Postgres catalog's lost-race path is read, not run | Low | the extension (`glossql_runner.cpp`) | With a Postgres catalog in CI | |
| A replace load of identical rows builds a new table, so results are computed once more. Comparing costs 60 to 160% of the load (1.00 s on 2,000,000 rows), so it is not built | Low | the extension | Not planned |
| The outlook and plan kits are tested against the suite's stand-in service only; a run against glossthesi `976842b` (it loads models) has not been made. The forecast is one result per metric, which loses the service's joint forecast of a request's series (better or level on 18 of 21 datasets by its own measurement): the project lead decides per metric or per dataset. The scenario path is about 300 of the outlook kit's 841 lines | Medium until run | `kits/outlook/kit.sql`, `../glossthesi` | Before the pull requests | |

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
- **`next`** has, per row, a kind of work (integrate, describe,
  test, review) and a level: must (served data is wrong or cannot be
  served), should (the layer is incomplete for what is served), could
  (what sits beside). Work on a dataset is complete with no must
  open; the closing line of a call counts must and should. `next`
  names no kit: a kit's tests and its stored results that are out of
  date come in through `view_tests()` and `glossql_outdated()`, and a
  function nobody ran is no row. A server runs without the outlook
  kit.
- **The outlook kit** (841 lines, 1,557 before) holds what needs the
  model service: `metric_ranges` on the dataset, `metric_forecast`
  and `metric_scenario` on a metric, the range test. The service
  returns the verdicts and the kit stores and serves them. **The plan
  kit** (323 lines) compares a plan with its metric's actuals with no
  model service; its forecast column reads a stored forecast. Both
  are pull-ins.
- **Gone**: the inputs derived from a body's bound plan, the lineage
  computed in C++ with its widenings, the filter on what a running
  function sees, `glossql_parts()`, the outlook kit's hand-made
  inputs digest, `forecast_exists`, `scenario_exists`,
  `fan_out_check` and `validity_check` as two, `open_items`, the
  console's re-measure button. `glossql_runner.cpp` went from 2947 to
  2401 lines in the last step.
- **A body that reads past the read functions is refused** at its
  declaration (`untracked_read`): the catalog reached directly, a
  what or where that is not a constant, a where that is no place.
- **A keyed load of identical rows** writes nothing and leaves the
  table's version (1.3 s against 2.0 s on 2,000,000 rows; a load
  where every row changed 2.3 s against 2.0 s).
- **Two writers at once** each land once; a test in
  `crates/duck/tests` holds it.

## Measured

Server at `df43dd8`: 119 tests pass. Extension at `b0478d1`: its SQL
suite passes with 2990 assertions, lint clean. The extension's
changes since `96b34b7` were reviewed line by line by two reviewers;
the confirmed findings are fixed, each with a test. glossval's series
capture equals each metric's own SQL (0 differing cells) and its
import path agrees with a fresh load. On the server on
127.0.0.1:8080 with the Formula 1 data (9 tables, 4 metrics, 1 table view), each
write one MCP call:

| Write | Before any lineage | With the read functions |
|---|---|---|
| `meaning` on a column no metric scans | 1.00 s, 4 results computed | 0.44 s, 0 |
| `meaning` on a table two metrics scan | 1.00 s, 4 | 0.44 s, 0 |
| `role` on a source column of a metric | 1.17 s, 4 | 0.44 s, 0 |
| `role` on a column a metric serves | not measured | 0.75 s, 1 |
| The same annotation again; a new property declared | not measured | 0.44 s, 0 |
| A relationship declared between tables no metric joins | 3.2 s, 12 (with the C++ lineage) | 0.44 s, 0 |
| A table view defined over three tables | not built | 1.99 s, 10: 7 column profiles, 1 relationship check, its join and orphan checks |
| A relationship declared that the table view joins over | not built | 0.87 s, 2: the relationship check and the view's orphan check |
| `meaning` on a column the table view reads | not built | 0.45 s, 0 |

Per call, reported by the build and not repeated here:
`results_due()` 0.10 s, `next` 0.34 s, the currency check over 23
results and 89 inputs 0.06 to 0.07 s. On the goals fixture: with two
plans stored, a change to one leaves the other current; an unrelated
annotation, an added assumption and a declared plan leave the
dataset's preview measurements current.

## Next issue (draft)

**The harmonisation kit** (`harness.md`, the first backlog row). The
outlook cut closes this plan's last medium row before it.
