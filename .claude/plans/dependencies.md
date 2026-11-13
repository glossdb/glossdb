# Dependency plan

How glossdb knows that a stored result is still valid, and who brings
it current. It works as a build system does.

The model is `model.md`, agreed with the project lead. In three
sentences:

1. **A function's body says what it reads**, through three read
   functions whose arguments are a what and a where on the lineage's
   edges: `annotations(property, where)`, `results(function, where)`,
   `definition(where)`. The list is taken from the body as written
   (its JSON) when the function is declared, and stored with it.
2. **A stored result keeps what those reads returned**, as a digest,
   and DuckLake's version of each table it scanned.
3. **A result is current while those hold the same**, and no result
   it read is outdated. Otherwise it is outdated: served and marked.
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

## Building the model, in this order

Each step ends with both suites passing and the Formula 1
measurement repeated.

| # | Step | What it touches | State |
|---|---|---|---|
| 1 | The edges as one relation; the three read functions and the places (itself, its columns, its sources, the columns it joins on, its relationships, its metric, the dataset); the reads of a body taken from its JSON at declaration and stored with the function | the extension | built |
| 2 | `relationship_coherence` stores one result per relationship; the bodies of the extension's kits and of the views kit read through the read functions; `fan_out_check` and `validity_check` are one; a test holds every shipped body to the read functions | the extension's kits, `kits/views/kit.sql`, both suites | built |
| 3 | The outlook kit's bodies the same; its hand-made inputs digest, `forecast_exists` and `scenario_exists` go | `kits/outlook/kit.sql` | built |
| 4 | A result's inputs are what its reads returned; the inputs derived from the bound plan, the lineage computed in C++ and the filter on what a running function sees go | the extension | in work |
| 5 | `SPEC.md` §6 says the model; `docs/inputs.md` | the extension; the project lead reviews | |

Done when, on the Formula 1 workspace: `meaning` on a table two
metrics scan computes 0 results (2 today); `role` on a column one
metric serves computes 1; an annotation outside every metric
computes 0.

## Open after that, in risk order

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| A view's lineage is per view. Per output column (`value` is `sum(points)`) it is finer; the parsed SQL as JSON (`json_serialize_sql`) gives the expression of each column | Low | the extension or a kit read | After | |
| What a currency check costs with the digests is not measured. A write that computes nothing takes 0.64 s, of which `next` 0.38 s and `results_due()` 0.10 s twice | Medium until measured | the extension, `kits/goals/kit.sql`, `crates/serverd/src/mcp.rs` | After | |
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

**The edges and the read functions.** What it buys: a function's
body can say what it reads in three calls, and the catalog serves
the lineage as one relation a person or an agent can query. What is
there: the spike's `reads.sql`, `bodies.sql` and `extract.sql`
(scratch); `glossql_views_scans`, `glossql_views_joins`,
`glossql_views_lineage`, `glossql_columns`, the relationships. Done
when: `edges` serves `contains`, `reads`, `relates` and `plans` for
a dataset; the three read functions return one row per asset of the
place for the subject of the running function; a function's row in
the catalog carries the reads taken from its body; the spike's three
bodies return what today's return on the kits' fixtures.
