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
| The catalog's relations stay our own tables in the catalogue database (Postgres or a DuckDB file) and take DuckLake's pattern for its own catalogue tables: each row has a begin and an end marker from a number that two writers cannot share. This replaces `seq` and the store version. Removing an annotation sets the end marker; no row is deleted | High: every read and write of the extension's store; `SPEC.md` §5 | the extension (`glossql_store.cpp`, `glossql_runner.cpp`) | First | |
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

## What DuckLake does with its own catalogue tables

Read on scratch lakes (DuckDB 2.0.0; a DuckDB file and Postgres 18 as
the catalogue):

- Every row of `ducklake_table`, `ducklake_view`, `ducklake_tag` and
  the others has `begin_snapshot` and `end_snapshot`. A replaced or
  removed row gets an end; it is not overwritten or deleted.
- The number is the id of the commit's snapshot. `ducklake_snapshot`
  has a primary key on it, so two commits cannot share one; the later
  one is tried again.
- `ducklake_snapshot_changes` says per snapshot what changed, with an
  author, a message and a free field.
- Expiring snapshots is explicit. It removes the change log of the
  expired snapshots; the server does not do it and closes the call to
  agents.

Ruled out by the project lead: storing the catalog's relations as
DuckLake tables (inlined or in Parquet).

## The design

1. **The catalog's relations stay our tables in the catalogue
   database**, beside DuckLake's. Each row gets a begin marker when it
   is written and an end marker when it is replaced or removed.
2. **The number comes from one source two writers cannot share.**
   Which source is the open point below.
3. **The version of a relation** is the highest begin or end marker of
   its rows. A removal moves it, because it sets an end.
4. **A kept read is keyed by** its text, its parameters, the dataset
   and the versions of the relations and data tables its plan reads.
   A changed relation gives another key; old entries leave by LRU.
5. **A plan names what it reads.** The glossary and the test results
   are queries over the relations.
6. **A response of the model service is kept by content.** The key is
   a hash of the route and the request body, plus the service's
   version from the answer.

## Open

- **Where the number comes from.** A catalog write makes no snapshot,
  so the lake's snapshot id is not it. Candidates: a sequence in the
  catalogue database; a counter row updated in the write's
  transaction. Not verified: how each behaves through DuckDB's
  Postgres attachment, and whether the write and the number are one
  transaction there.
- The glossary as of a version of the data needs the lake's snapshot
  on each row beside the marker, as glossary rows have today.
- A miss still costs the planning of a large read (0.3 to 0.4 s).
  Making `next` and `view_tests()` smaller is separate work.
- An identical reload still changes a table's version.

## Next issue (draft)

**Begin and end markers on the catalog's relations.** What it buys: a
version per relation and one order of rows under concurrent writes.
What is there: `Inner::Seq`, `StoreVersionSQL` (`:1677`), `PartsSQL`
(`:389`), the delete (`:1031`) in `glossql_store.cpp`; the
reproduction of duplicate `seq`. Done when: the open point on the
number is answered by a test on both catalogues; the eleven relations
carry the markers; `seq` and the store version are gone; `DELETE FROM
glossary` sets an end; a test writes annotations from 8 connections
and finds one order; both suites pass.
