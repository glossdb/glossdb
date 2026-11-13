# Dependency plan

How glossdb knows that a stored result is still valid, and who brings
it current. It works as a build system does.

1. **Lineage is the model.** A function runs on a subject: a column,
   a table, a view or the dataset. Its result depends on that subject
   and its lineage, and on nothing else: for a view, its columns, its
   definition and the tables and columns it scans and joins on; for a
   table, the tables its relationships connect it to; for the
   dataset, everything in it. While a function runs it sees the
   glossary and the results of that lineage only, so the rule holds
   by construction.
2. **A stored result keeps what it read** (`inputs`): the lineage it
   was drawn from, a digest of the glossary and result rows in it as
   they held, and DuckLake's version of each table and view. Nobody
   declares them.
3. **A result is current while those rows hold the same** and each
   table and view has that version. Otherwise it is outdated: served
   and marked. A result that read an outdated result is outdated. A
   change that is undone makes it current again.
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
| An annotation of any property on an asset in a metric's lineage outdates its `additivity_check`, also a property the check does not read (`meaning` on a scanned table: 2 results computed, 0 expected). The kit read of the views' definitions names no property | Medium: wrong grain, one level left | `kits/views/kit.sql` (`view_rows()`), the extension: a read keyed by subject and property | Next | drafted below |
| The lineage is wider than what is read in three places: a view's lineage holds the results stored on the dataset, a plan holds its metric, a table holds every table its relationships reach (on connected data, the whole dataset) | Medium | the extension (`ClosureOf`, `glossql_runner.cpp`) | After | |
| A view's lineage is per view. Per output column (`value` is `sum(points)`) it is finer; the parsed SQL as JSON (`json_serialize_sql`) gives the expression of each column | Low | the extension or a kit read | After | |
| What a currency check costs with the digests is not measured. A write that computes nothing takes 0.64 s, of which `next` 0.38 s and `results_due()` 0.10 s twice | Medium until measured | the extension, `kits/goals/kit.sql`, `crates/serverd/src/mcp.rs` | After | |
| `SPEC.md` §5.2, §5.3, §6 and `docs/inputs.md` are edited for the model as built | Low; the project lead reviews | the extension, commits `9b7a121` to `b3c1b8b` | Before the pull request | |
| An outdated result no view needs, and an outdated annotation on an asset no view reads, are listed nowhere and nobody is asked to bring them current | Low | `kits/goals/kit.sql` (`next`) | Open | |
| An identical reload moves the table's version: the merge updates every matched row, the replace builds a new table | Low: results are computed once more | the extension (`glossql_runner.cpp`) | When measured as a cost | |
| The preview measurements are due by the outlook kit's own rule (`outlook_due()`), listed by `next`; a response of the model service is kept under a hash of the request and the service's version | Medium | `kits/outlook/kit.sql`, the extension's service call | With the outlook issue (`harness.md`) | |
| Newest-row windows left in the outlook kit and the console's frames | Low | `kits/outlook/kit.sql`, `crates/apps/builtin/console/frames` | With the outlook issue | |

## What is built

- **One write, one transaction** (`Inner::Write`). A catalog write
  takes the lake's next snapshot id with its rows. A new row ends the
  row it replaces (`end_snapshot`); no row is deleted. `<name>` serves
  the current rows, `<name>_history` every row. A view's DuckLake row
  is in the transaction of its glossary row. A write is tried again
  only when another writer took its snapshot id; any other error is
  refused on the first try (5.3 s and "lost 60 races" before, 0.005 s
  and the error itself now; the Postgres case is read, not run).
- **Inputs are rows**, written with the result: one `closure` row
  with the lineage's members, a digest per glossary or result read
  over the lineage's rows (asset, property, actor, value and the
  outdated mark; for results asset, function, value and error), and
  the versions of tables, views and the dataset's shape. The shape is
  a digest of the columns and views as they are, so a load in place
  of a table with the same columns leaves every result current.
- **A function sees its lineage only.** The catalog's views filter
  by it while a function runs; a body that reads past them is
  refused.
- **A computation that fails is a result**: stored with its inputs
  and its error, current, so the server does not try it after every
  write. A direct call computes it again.
- **Snapshot expiry**: an annotation whose earlier catalog row is
  gone reads as outdated.
- **`results_due()`** is in `kits/goals/kit.sql`. What a metric
  wants: the profile of each column it reads or joins on, the
  relationship check of its dataset, the measurement its row names as
  not run, and the tests on it and on what it reads.
- **The server** (`bring_current` in `crates/duck/src/lib.rs`) runs
  it after a write, in rounds, before the next read of the same call.
  The console has no re-measure button.
- **`next`** reads the catalog's states and `load_changes()` (what
  the newest load changed in a table). `open_items`, the older list
  beside it, is removed.

## Measured

Server at `2bc5f2b`: 115 tests pass. Extension at `b3c1b8b`: its SQL
suite passes with 2609 assertions, lint clean. On the server on
127.0.0.1:8080 with the Formula 1 data (9 tables, 4 metrics), each
write one MCP call:

| Write | Before the lineage model | Now |
|---|---|---|
| `meaning` on a column no metric scans | 1.00 s, 4 results computed | 0.64 s, 0 |
| `role` on a column one metric scans | 1.17 s, 4 | 1.02 s, 1 |
| `meaning` on a table two metrics scan | 1.00 s, 4 | 1.22 s, 2 (0 expected: first open row) |
| The same annotation again | not measured | 0.64 s, 0 |
| A new property declared | not measured | 0.64 s, 0 |
| A read that writes nothing | 0.02 s | 0.02 s |
| `next`, read whole; `results_due()` | 0.36 s; 0.10 s | 0.38 s; 0.10 s |

A catalog write that fails for a reason other than a lost race: 5.3 s
and "lost 60 races" before, 0.005 s and its own error now (the
Postgres case is read, not run).

## Next issue (draft)

**A result is outdated by the properties it read, not by any property
in its lineage.** What it buys: an annotation of `meaning` on a table
a metric scans computes nothing; today it computes `additivity_check`
for each metric that scans it. What is there: `view_rows()`
(`kits/views/kit.sql`) reads the views' definition rows from the
glossary with no property named, so the result's digest covers every
property in the lineage; the reads that name a property are digested
per property already. Done when: the read of a view's definition is
keyed by the view; on the Formula 1 workspace `meaning` on
`f1.standings` computes 0 results and `role` on `f1.results.points`
still computes 1.
