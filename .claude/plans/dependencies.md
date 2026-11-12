# Dependency plan

How glossdb knows that a result is still valid, and how a read is
served again without being computed again. This is a caching problem:
filled on read, keyed by versions, evicted by LRU. A key works when it
names every input by a version the storage guarantees. Today the
catalog has no such version. This plan is a proposal; nothing in it is
built. `DEPENDS ON` and the server's result cache were built and are
reverted.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The project lead agrees or changes "The design" below | — | this file | Next | |
| The catalog's relations are kept by DuckLake: tables in the catalogue database with DuckLake's row id and begin and end snapshot, in place of `seq`, the store version and `snapshot_id` on glossary rows. Removing an annotation appends a row | High: every read and write of the extension's store; `SPEC.md` §5 | the extension (`glossql_store.cpp`, `glossql_runner.cpp`) | First | |
| One key rule for a stored result and a kept read: the text and the versions of the relations its plan reads | Medium | the extension (`PartsSQL`, `Cached`) | Second | |
| The glossary and the test results are queries over those relations, so a plan names what it reads and no result records "everything" | Medium | the extension, the kits | With the second | |
| A response of the model service is kept under a hash of the request | Medium | the extension (`glossql_service.cpp`) | Third | |
| The server keeps a read's result, keyed by SQL, parameters, dataset and the versions of what the plan reads | Low | `crates/duck/src/lib.rs` | Fourth | |
| The checks of one call run on separate connections | Low | `crates/duck/src/lib.rs` (`built_in_tests`) | Fifth | |
| A property that carries a test's expectation is required only where it is annotated | Medium: `SPEC.md` §5 | the extension (`GLOSSARY()`), six console frames | With the second | |

## The facts today

- **Data tables** are DuckLake tables. A load is a commit and makes a
  snapshot. The change log names the tables a snapshot changed.
- **The catalog** (glossary, measurements, tests, properties,
  functions, relationships, load queries, loads, sources, datasets,
  kits) is eleven plain tables `glossql_*` in DuckLake's catalogue
  database. A write to them is not a lake commit. **It makes no
  snapshot.**
- **Rows are appended**, with one exception: `DELETE FROM glossary`
  (`SPEC.md` §5.2) deletes rows.
- **`seq` is not unique.** It is "highest so far plus one", read
  without a lock. Measured: 24 annotations from 8 connections gave 182
  rows and 166 distinct `seq`; one value was shared by 7 rows. The
  newest annotation is chosen by `seq`.
- **The store version** is a fingerprint: the lake's snapshot joined
  with the highest `seq`, the row count and the newest timestamp of
  each of the eleven tables. Any write changes it, so each write
  empties the three reads and the views kept under it.
- **60 of 88 stored results** on the Formula 1 workspace record
  "everything" as what they read: the glossary is read through a table
  function a plan cannot see into.
- **The glossary read contains the stored results**, so a stored
  result changes it.
- **Not inputs of a read:** the clock (no kit or console frame uses
  it), the actor (writes only), the kits' views and macros (fixed
  while the server runs).
- **The model service** is called in 5 places, all in functions that
  store a result. The request carries the series. The response carries
  the service's version.

Measured on the Formula 1 workspace (9 tables, 5 views, 3 metrics):

| Call | Time |
|---|---|
| Any agent call, of which the closing read of `next` 0.46 s | 0.51 s |
| `next` with `LIMIT 0`: planning only | 0.29 s |
| `GLOSSARY()` from the object cache | 0.011 s |
| An annotation on a table a view scans: 12 checks one after another, each refilling the glossary | 6.0 s |
| Eight reads of `next` at once, wall time | 0.80 s |

## What DuckLake does (DuckDB 2.0.0, measured on scratch lakes)

DuckLake stores a small write to a table in its catalogue database and
makes a snapshot of it (data inlining; on by default up to 10 rows per
write). The same results on a DuckDB file and on Postgres 18 as the
catalogue, unless two numbers are given.

| | Result |
|---|---|
| 200 single-row writes | 0.5 s / 1.1 s, 200 snapshots, no Parquet file |
| 400 writes from 8 connections | 2.9 s / 4.3 s, no error, 600 distinct row ids |
| A row's `rowid` and `snapshot_id` | set at commit; the same after a flush to Parquet and after older snapshots expire |
| A function stores a result while another transaction is open | both commit; the open one does not see the result until it ends |
| Two transactions insert into one table | both commit |
| A delete beside an insert or a delete on the same table | the later commit fails with a conflict |
| A delete | the row gets an end snapshot; older versions still read it |
| A flush to Parquet | a snapshot of its own (`flushed_inlined`); no automatic flush |
| Expiring snapshots | explicit only; the change log of the expired snapshots is gone, the rows stay |
| Author, message and a free field per commit | `set_commit_message` |
| A read of 55 scans, planned / run | 3 ms / 17 ms; plain tables 2 ms / 6 ms |

Two versions of a table follow, and they differ:

- **The last snapshot that changed it**, from the change log. A flush
  moves it though no row changed. Expiry removes it. The parts of data
  tables use this today.
- **The highest `snapshot_id` of its rows.** A flush and expiry leave
  it as it was. A delete does not move it.

## The design

1. **DuckLake keeps the catalog's relations.** They stay catalogue
   tables; DuckLake adds the row id and the begin and end snapshot.
   Every write is a commit. The commit carries who wrote and why.
2. **Catalog relations are append only.** Removing an annotation
   appends a row that says so. Then concurrent writers do not
   conflict, and the version of a relation is the highest
   `snapshot_id` of its rows. The newest annotation is the one with
   the highest `rowid`.
3. **One key rule.** A result is valid for the text that computed it
   and the versions of the relations its plan read. Example: a profile
   of `results.grid`, computed by `column_profile` when `results` was
   at 41, holds while the function's text is the same and `results` is
   at 41. A load into `races` does not touch it. Nothing is
   invalidated: a changed relation gives another key, and old entries
   leave by LRU.
4. **A plan names what it reads.** The glossary and the test results
   are queries over the relations. A check that reads annotations is
   keyed on `glossary`; a stored result moves `measurements` only.
5. **A response of the model service is kept by content.** The key is
   a hash of the route, the request body and the service's version.
   The body carries the series, so an identical reload is a hit. This
   is the action cache of build systems.
6. **The grain is the relation.** Finer grains (per dataset, per
   property) come when a measurement asks for them.

## Open

- The version of a data table: the change log (today) or the highest
  `snapshot_id` of its rows. The second costs a scan of a large table
  and misses deletes; the first is lost when snapshots expire. The
  server does not expire snapshots and closes the call to agents.
- A miss still costs the planning of a large read (0.3 to 0.4 s).
  Making `next` and `view_tests()` smaller is separate work.
- An identical reload still changes a table's version.
- Not measured: `next` itself over lake-kept relations; a working
  day's number of snapshots on a real workspace.

## Next issue (draft)

**DuckLake keeps the catalog's relations.** What it buys: a version
per relation that the storage guarantees, unique row order under
concurrent writes, the glossary as of a version of the data by time
travel. What is there: the store's relations and `Inner::Seq`
(`glossql_store.cpp`), `StoreVersionSQL` (`:1677`), `PartsSQL`
(`:389`), the delete (`:1031`); the scratch measurements above. Done
when: the eleven relations are DuckLake tables; `seq`, the store
version and `snapshot_id` on glossary rows are gone; `DELETE FROM
glossary` appends; a test writes annotations from 8 connections and
finds one order; `SPEC.md` §5 says the same; both suites pass.
