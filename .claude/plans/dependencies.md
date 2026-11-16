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
| Not tested: an interrupt during a computation is not stored as a failed result (the server's interfaces expose no interrupt); the Postgres catalog's lost-race path is read, not run | Low | the extension (`glossql_runner.cpp`) | With a Postgres catalog in CI | |
| A replace load of identical rows builds a new table, so results are computed once more. Comparing costs 60 to 160% of the load (1.00 s on 2,000,000 rows), so it is not built | Low | the extension | Not planned |

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
  are pull-ins, run over MCP against glossthesi `976842b` (Measured).
- **Gone**: the inputs from a body's bound plan, the C++ lineage,
  `glossql_parts()`, `forecast_exists`, `scenario_exists`,
  `open_items`, the console's re-measure button.
- **A write that computes nothing takes 0.24 s** (0.54 s before; a
  release build 0.28 s). Which results are out of date is checked
  once per store version and kept; a kit's table macro is kept the
  same way (`glossql_kept()` in the extension), so `view_tests()` and
  the views' summary are planned once per write; `next` has no
  correlated subquery. A kit's rows enter `next` as data in the kept
  reads, so a kit no longer adds planning time. What `next`,
  `results_due()` and the closing lines return is unchanged on the
  Formula 1 and the three-systems walk. Left: the out-of-date check
  (0.06 s) is computed whole on each write.
- **A body that reads past the read functions is refused** at its
  declaration (`untracked_read`): the catalog reached directly, a
  what or where that is not a constant, a where that is no place.
- **A keyed load of identical rows** writes nothing and leaves the
  table's version (1.3 s against 2.0 s on 2,000,000 rows; a load
  where every row changed 2.3 s against 2.0 s).
- **Two writers at once** each land once; a test in
  `crates/duck/tests` holds it.

## Measured

Server: 121 tests pass. Extension at `3fa3d78`: its SQL
suite passes, lint clean; its changes since `96b34b7` were reviewed
line by line by two reviewers, the findings fixed with a test each.
glossval's series capture equals each metric's own SQL. On the Formula
1 data (9 tables, 4 metrics, 1 table view), one MCP call each: an
annotation or a relationship no view's checks read 0.24 s, 0 results
(1.00 to 3.2 s, 4 to 12, before the read functions); `role` on a
served column 0.46 s, 1; a table view over three tables 1.73 s, 10.
Per write: `results_due()` 0.15 s, `next` 0.05 s, the write 0.008 s.

**The outlook and plan kits against glossthesi `976842b`**, over MCP
on the MTA subway data (48 months sent; two metrics with dimensions,
a 4-month metric, a plan, three scenarios). Each function, read, code
and refusal holds as used; a load puts each stored result out of date
in `next` and calls no service; an unrelated annotation leaves them
current. Per call: ranges 0.7 to 1.4 s, forecast 0.7 s, scenario 2.3
to 3.5 s, plan 1.0 s. Fixed on the way: a temporal profile out of
date after a load kept every result out of date; a short metric read
`history_short` with one month; no `coverage_datasets`; a failed
scenario run not served; a service that does not answer not classed
`service_failed` (the extension).

Each metric in its own request against a dataset's two in one,
one-step backtest at 24 origins on 48 months, measured. Quantile loss
as % of the mean actual; share inside 10-90 and 5-95; alone / together:

| Dataset | Metric | Loss % | Inside 10-90 | Inside 5-95 |
|---|---|---|---|---|
| MTA subway | trains run | 0.74 / 0.70 | 0.75 / 0.75 | 0.92 / 0.92 |
| MTA subway | trains scheduled | 0.70 / 0.71 | 0.79 / 0.83 | 0.96 / 0.96 |
| BIRD bank | transactions | 1.63 / 1.64 | 0.88 / 0.88 | 0.88 / 0.88 |
| BIRD bank | amount | 1.40 / 1.46 | 0.92 / 0.96 | 0.96 / 0.96 |
| rel-stack | votes | 1.39 / 1.38 | 0.79 / 0.79 | 0.92 / 0.96 |
| rel-stack | edits | 1.29 / 1.31 | 0.83 / 0.83 | 0.96 / 1.00 |

Per metric costs nothing measurable: at most 0.06 points of loss, 1 in 24 inside a range.

## Next issue (draft)

**The harmonisation kit** (`harness.md`, the first backlog row).
