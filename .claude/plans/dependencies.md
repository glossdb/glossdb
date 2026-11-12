# Dependency plan

How glossdb knows that a stored result is still valid, and who brings
it current. It works as a build system does.

1. **Everything a result can read has a version**: a table, a view, a
   relation of the catalog or one property of it, the lake's shape.
   `glossql_parts()` serves each version as it is now.
2. **A stored result keeps what it read**, one row per input at the
   version read (`inputs`). The inputs come from the plan of the
   function while it runs; nobody declares them.
3. **A result is current while every input still has that version.**
   Otherwise it is outdated: it is served and marked.
4. **One read says what is due**: `results_due()` lists the results a
   dataset's views want that are missing or outdated, with the
   statement that computes each, an input before what reads it.
5. **Three readers of that one read.** The server runs it after a
   write, until nothing is left. The console's re-measure runs it with
   the preview measurements (`preview := true`): those call the model
   service (`../glossthesi`), and a person starts them. `next` lists what is
   left over: what only an actor can do (a statement to write, a red
   test, a decision, a preview measurement that is due).

A result no view wants is not due. Nothing else decides what is
computed: no second list, no flag.

## Open, in risk order

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| A catalog write treats every SQL error as a lost race: a real error is tried 60 times with waits and reported as 60 lost races | High: a bug; every write path | the extension (`CatalogWrite::Run`, `glossql_runner.cpp:215-280`) | Next | drafted below |
| A replace load is `CREATE OR REPLACE TABLE`. If that moves the lake's shape, every lineage result, column listing and glossary read is outdated after each load. Read from the code, not tested | High until tested | the extension: a test first (`glossql_store.cpp:433`, `glossql_runner.cpp:565`) | With the row above | |
| A result that read results is outdated when one of them is (rule 3, applied through). Today a glossary read of a property a function fills names the whole glossary, six catalog relations and the lake's shape instead, so any declaration or load anywhere outdates every such reader; `additivity_check` runs again on every annotation (4 results, 0.4 s) | Medium: it replaces the branch in `NameRead` and its fixed inputs; `results_due()` already runs inputs first | the extension (`glossql_store.cpp:1797-1816`), `kits/views/kit.sql` | After the two rows above | |
| A computation that fails is a result too: stored with its inputs and its error, served as the error while current. Today nothing is stored, so a check that fails every time is due after every write | Medium: a column on `measurements`; a workspace is rebuilt | the extension (`glossql_runner.cpp:1328-1361`) | After | |
| Snapshot expiry. A table's version comes from the snapshot that last changed it, so expiry recomputes once. If expiry removes ended column or view rows, an outdated annotation reads as current | Medium: not tested | the extension: a test first; a missing earlier row counts as outdated (`glossql_store.cpp:1258-1318`) | Before a workspace expires snapshots | |
| `SPEC.md` says "data version" in seven places (§5.2, §6, §7, §7.2); §6 lists six of the nine input forms and does not say that a function declared again outdates its results | Low; the project lead reviews | the extension: `SPEC.md`, `grammar.ebnf` comments, `docs/inputs.md`, README | With the rule above, one diff | |
| An identical reload moves the table's version: the merge updates every matched row, the replace builds a new table | Low: results are computed once more | the extension (`glossql_runner.cpp:565-574`) | When measured as a cost | |
| The read cache is keyed by the lake's snapshot, results by their inputs: two version schemes | Low | the extension (`StoreVersion`) | When measured as a cost | |
| The preview measurements are due by the outlook kit's own rule (`outlook_due()`), joined into `results_due(preview := true)`; a response of the model service is kept under a hash of the request and the service's version | Medium | `kits/outlook/kit.sql`, the extension's service call | With the outlook issue (`harness.md`) | |
| `next` takes 0.35 s per read; the MCP interface keeps its rows per lake snapshot, the console reads it whole | Low | `kits/goals/kit.sql`, `crates/serverd/src/mcp.rs` | When measured as a cost | |
| Newest-row windows left in the outlook kit and the console's frames | Low | `kits/outlook/kit.sql`, `crates/apps/builtin/console/frames` | With the outlook issue | |

## What is built

- **One write, one transaction** (`Inner::Write`). A catalog write
  takes the lake's next snapshot id with its rows. A new row ends the
  row it replaces (`end_snapshot`); no row is deleted. `<name>` serves
  the current rows, `<name>_history` every row. A view's DuckLake row
  is in the transaction of its glossary row.
- **Inputs are rows**, written with the result, their versions read
  before the result is computed. Forms: a table or view, a catalog
  relation, one function's results, one property of the glossary,
  `<dataset>.*`, `<dataset>.**`, `lake.shape`.
- **`results_due()`** is in `kits/goals/kit.sql`. What a metric
  wants: the profile of each column it reads or joins on, the
  relationship check of its dataset, the measurement its row names as
  not run, and the tests on it and on what it reads.
- **The server** (`bring_current` in `crates/duck/src/lib.rs`) runs
  it after a write, in rounds, before the next read of the same call.
  The console's re-measure calls the same function.
- **`next`** reads the catalog's states and `load_changes()` (what
  the newest load changed in a table). `open_items`, the older list
  beside it, is removed.

## Measured

Server at `e42e21e`: 126 tests pass. Extension at `96b34b7`: 19 test
files, 2128 assertions. On the server with the Formula 1 data (9
tables, 4 metrics):

| What | At the start | Now |
|---|---|---|
| A call that writes nothing | 0.48 s | 0.005 s |
| An annotation on a table two metrics scan | 3.3 s, 8 results computed | 1.0 s, 4 computed |
| One row added to a table two metrics scan | not measured | 2.4 s, 17 computed |
| Results out of date after the setup | 3 | 0 |
| A refill of a dataset's glossary | 0.25 s | 0.04 s |
| One annotation write, 250 in a call | | 14 ms |
| `next`, read whole; `results_due()` | | 0.35 s; 0.10 s |

Where a writing call's second goes: `next` 0.35 s, four
`additivity_check` runs 0.4 s, `results_due()` twice 0.1 s.

Learned on the way: a snapshot with no lake change takes a NULL
change text, DuckLake's own form; the lake and the catalogue database
cannot be written in one transaction, and there is no `SAVEPOINT`;
the staleness rule for annotations is joins (6 ms), not subqueries
per row (98 ms).

## Next issue (draft)

**A catalog write reports a real error as itself.** What it buys: a
write that fails for a reason other than a lost race fails at once
with its own error, where today it waits through 60 tries and names
the wrong cause. What is there: `CatalogWrite::Run`
(`src/glossql_runner.cpp:215-219`) maps every error to `LostRace`;
the retry loop is at `:247-280`. Done when: only a conflict on the
snapshot row is retried; a test writes a row that breaks a constraint
and gets that refusal on the first try; a second test loads a table
again in place and asserts whether `lake.shape` moved, which settles
the second row of this plan.
