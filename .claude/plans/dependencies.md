# Dependency plan

How glossdb knows that a result is still valid, and how it is brought
current. The frame is a build system: inputs with versions (data
tables, annotations, declarations), rules (functions, tests, views),
results, and for each result a trace of what it read at which
version. A result is out of date when an input of its trace has
another version. Dependencies are found while a rule runs, from its
plan, as Shake and the Rust compiler's queries do. Nothing here is
committed.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| `begin_snapshot` and `end_snapshot` on the catalog's relations; a catalog write takes the lake's next snapshot id in the transaction that writes its rows; the views serve the current rows, `<name>_history` every row | — | both repositories | Built | |
| A view definition's DuckLake row is in that transaction; a load record carries the id of the load's own commit | — | the extension | Built | |
| The staleness rule for annotations as joins; the values of a refill read once | — | the extension | Built | |
| The trace is rows: the `inputs` relation, one row per input a stored result read, at the version read; current by a join; `glossql_parts()` serves each input's version now. `data_version` and `reads` are gone | — | the extension | Built | |
| A read names what it serves: annotations by property, the lineage functions the lake's shape, a glossary read its property; two checks pass the property | — | the extension, `kits/views/kit.sql` | Built | |
| After a write the server computes the results the kit's `results_due()` lists, an input before what reads it, until none is left; the matching of outcome text is gone | — | `crates/duck/src/lib.rs`, `kits/views/kit.sql` | Built | |
| The interface keeps a dataset's `next` rows while the lake's snapshot holds | — | `crates/serverd/src/mcp.rs` | Built | |
| After a write the server runs a metric's measurement that nobody ran (the grain of its period column), so a series serves after its definition | — | `kits/views/kit.sql` | Built | |
| `view_summary()` reads the whole glossary, so `additivity_check` runs again on every annotation (4 results, 0.4 s). One of the five properties it reads is filled by a function, so naming the properties is not enough: the read must say that it takes an outdated value too | Medium | `kits/views/kit.sql`, the extension | After the release candidate | |
| `next` read again after a write costs 0.37 s, 0.27 s of it the preview arm on a workspace with no forecast or plan | Medium | `kits/goals/kit.sql`, `kits/outlook/kit.sql` | With the outlook | |
| `next` is what the system cannot bring current itself: a missing input only an actor can give, a red test, a decision that waits. Read row by row, it already was, except the profile above and the preview measurements that are due | Low | `kits/goals/kit.sql`, `kits/outlook/kit.sql` | The preview measurements with the outlook | |
| The outlook kit keeps the request and the stored answer; the model service returns the verdict | Medium: the service is extended | `kits/outlook/kit.sql`, `../glossthesi` | After | |
| The kits read the current rows plainly: 81 newest-row windows become a read of the view | Low | the kits, the console's frames | After | |
| A function's macro and a dataset's schema are DuckLake's commits, each followed by its row; a removal leaves a view as it is | Low | the extension | After | |
| A response of the model service is kept under a hash of the request and the service's version | Medium | the extension (`glossql_service.cpp`) | With the outlook | |
| The checks of one call run on separate connections | Low | `crates/duck/src/lib.rs` | When measured as a cost | |
| One property as the kept unit of the glossary | Low: a refill is 40 ms | the extension | When measured as a cost | |
| A property that carries a test's expectation is required only where it is annotated | Medium: `SPEC.md` §5 | the extension, six console frames | Open | |

## What is built

- **One write, one transaction** (`Inner::Write`). It takes the lake's
  next snapshot id with its rows; a write that loses a race runs
  again, admission included. The change text is DuckLake's: NULL for a
  write to the catalog alone, `created_view` for a definition.
- **A new row ends the row it replaces**; `DELETE FROM glossary` ends
  rows. No row is deleted.
- **A view follows the serving definition**, a person's over an
  agent's, in the transaction of its glossary row.
- **Inputs are rows.** `<dataset>.*`, `<dataset>.**` and "every other
  function's results" are inputs too, their version a digest of their
  members. The versions are read before the result is computed.
- **Precise inputs.** A scan of the annotations filtered by property
  names that property. The lineage functions and the column listing
  name `lake.shape`, DuckLake's schema version. A glossary read of one
  property that no function fills names that property; any other
  glossary read names everything, since a stored result's currency
  depends on the data.
- **After a write** the server reads `results_due()` and runs what it
  lists, in rounds. The console's re-measure runs a function that read
  other functions' results after them, by its last trace.
- **`SPEC.md` §5.2 and §6** are edited for the markers and the
  `inputs` relation. The project lead reviews them.

## Measured

Extension: 19 test files, 2128 assertions, lint clean. Server: 126
tests, format and clippy clean. DuckDB 2.0.0; the write path also on
Postgres 18 by script.

On the server with the Formula 1 data (9 tables, 4 metrics):

| What | At the start | Now |
|---|---|---|
| A call that writes nothing | 0.48 s | 0.005 s |
| An annotation on a table two metrics scan | 3.3 s, 8 results computed | 1.0 s, 4 computed |
| An annotation on a column no metric scans | not measured; left results out of date | 1.0 s, 4 computed |
| One row added to a table two metrics scan | not measured | 2.4 s, 17 computed |
| Results out of date after the setup | 3 (`fan_out_check` ran before `column_profile`) | 0 |
| Results that record "everything" as an input | 16 of 28 | 0 of 28; `additivity_check` names the whole glossary |
| A refill of a dataset's glossary | 0.25 s | 0.04 s |
| One annotation write, 250 in a call | | 14 ms |
| Call times at 310 and at 1387 snapshots | | unchanged |

Findings behind the numbers:

- The staleness rule for annotations was subqueries per row: DuckDB
  planned it in 98 ms for 8 rows; as joins, 6 ms.
- A snapshot with no lake change takes a NULL change text, DuckLake's
  own form; an empty string breaks its conflict check.
- The lake and the catalogue database cannot be written in one
  transaction, and there is no `SAVEPOINT`.
- Each check quotes the metric's definition in its fix; the plan
  reader took that for the whole glossary until it read the filter.

## Open

- Where a writing call's second goes: `next` 0.37 s, four
  `additivity_check` runs 0.4 s, `results_due()` twice 0.1 s.
- `next` alone 0.11 s, its preview arm alone 0.12 s, together 0.37 s:
  not explained.
- The kept `next` rows live in the MCP interface; the console and an
  agent's own read of `next` read it whole.
- A check that fails every time stays due and is tried on every
  writing call.
- Snapshot expiry against markers that are snapshot ids: not tested.
- Separate work: an identical reload still changes a table's version.

## Next issue (draft)

**The model service returns the verdict of a forecast.** What it buys:
the outlook kit keeps the request and the stored answer and no longer
computes the comparison in SQL. What is there: `POST /forecast` with
`origins` already returns one result (score and state) over all
members (`../glossthesi/docs/contract.md`); `kits/outlook/kit.sql`
(1,613 lines) and its suite. Done when: the kit's tests read the
service's state, the kit is under half its size, both suites pass.
