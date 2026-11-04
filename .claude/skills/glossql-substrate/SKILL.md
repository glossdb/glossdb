---
name: glossql-substrate
description: How to build ON DuckDB and the glossql extension rather than around them — what each owns, the seams, the rules that come with them, and the laptop's sharp edges. Use before writing or reviewing any server code that opens the engine, runs a statement, reads the record, or adds a read, a measurement or a route.
---

# The substrate

glossql is a database built on DuckDB. The glossql extension owns the
language and the record; DuckLake owns the lake; this repository
owns the doors. A read is SQL the engine plans, a kit is SQL the
engine runs, a measurement is a SQL body the engine executes. Nothing
in Rust re-implements what the engine does, and nothing in Rust
computes what a kit can say in SQL.

The rule this skill exists to enforce: **either use the seam, or
write down why it is wrong for us.** "We didn't know" is the failure
mode; this file is so nobody has to rediscover it.

## Where the answers live

| topic | reference |
|---|---|
| the extension: grammar, store, subjects, reads, kits, conformance | `../gloss/README.md`, `../gloss/CONFORMANCE.md`, `../gloss/src/` headers |
| the kits and their suites | the language's: `../gloss/kits/<kit>/kit.sql`, `../gloss/test/sql/glossql_kit_<kit>.test`; the server's: `kits/<kit>/kit.sql` and `kit.test` beside it, run by `crates/duck/src/sqllogic.rs` |
| DuckDB's SQL, the release the lock resolves | `vendor/duckdb/sql/` (served as `doc://vendor/duckdb/sql/…`) |
| DuckDB's C API through Rust | the `duckdb-neo` crate at the version `Cargo.toml` names |
| DuckLake: the catalog, snapshots, the data path | ducklake.select, the `ducklake` extension |
| the engine facade | `crates/duck/src/lib.rs`, the crate header first |

## What each party owns

- **The extension** owns the statements of the language (parsed by
  its grammar on DuckDB's parser), the store (the relations as tables
  in the lake's catalog, served as `ws.glossql.*`), the record read
  (`GLOSSARY()`, `ATTEST()`, the collapse, the witnesses, the stale
  rule), the subjects (a dataset, a table, a column, a relationship,
  a source, a view and its columns), the lineage of views, the cells
  of a dataset (`dataset_cells`), a view kept per store version, the
  service call (`glossql_service`), and the kit loader (`glossql_kit`).
- **A kit** owns vocabulary about the data: aspects, functions,
  witnesses, table macros that read the record and the views, and
  its routes for the `next` read. A kit is SQL, the language's in
  `../gloss/kits/` and the server's in `kits/`, run at every open,
  with a `.test` suite beside it.
- **The server** owns the plane (one instance per process, opened
  once), a channel per call (one connection, the actor and the
  dataset set on it), the core and door kits (`kits/core`, `kits/door`),
  the composed `next` read, the doors and the pages.

## The seams, and the rules they impose

- **Every DuckDB call is synchronous.** It runs on the blocking pool
  (`spawn_blocking`) and hands its rows back as Arrow batches. Nothing
  of the engine's runs on the async runtime's threads; nothing of the
  runtime's is awaited inside an engine call.
- **One instance, a connection per call.** The instance holds the
  extension, the lake and the kits. A channel is a connection with
  the grammar on, the actor as session variables the extension reads,
  the dataset in use and a search path of the dataset's schema and
  the store's. No door keeps a cursor.
- **A read never writes.** The record read and the kept views are
  computed once per store version — the lake's snapshot and every
  relation's highest sequence — and served from the object cache; a
  write moves the version. An arm of `next` reads the record and
  never the data: what a goal judges is a measurement, read back.
- **A read is a table macro; a measurement is a function with a
  body.** A new read, measurement or route is a statement in a kit,
  never a change to the server. A macro's body is bound at CREATE,
  so a macro a kit's macro calls must stand before it in the file.
  A macro's named parameters spell `:=`; a measurement reads its
  subject as `$subject`.
- **A view's columns are subjects.** A metric's grounding stands as a
  view under its name, and the words that make it a series — role,
  behaviour, the ladder — are glosses on its columns. A re-gloss of
  the view retires its columns' glosses by the stale rule; the reads
  serve what the record says and re-mark nothing.
- **Measurements carry their legs.** A measurement stands while what
  it read — the data's snapshot and the record legs the function
  read — is unchanged, and is stale once one moved. A measurement is
  no leg of a pin: a route that must compare two measurements
  compares them itself.
- **A refusal is a value where the kit must stand.** The service
  call's soft form, `glossql.service_soft`, answers a refusal as
  `{"error": …}`; DuckDB's `TRY()` refuses volatile functions, so
  the soft form is the extension's.
- **The extension is pinned.** `crates/duck/glossql.ref` names the
  commit the build carries; the DuckDB release is the one `duckdb-neo`
  links, and the extension is built against the same one. A pin move
  is both at once, and the vendored guide follows.

## Before you write a mechanism

1. Can the kit say it in SQL? Then it is a macro, a function body or
   a route, with its `.test` beside it in the extension's repository.
2. Does the extension already have the seam — a subject kind, a read,
   a kept relation, the service call? Then use it; a missing seam is
   a change in `../gloss`, with its test, before anything here.
3. Is it the door's — a route composed, a page served, a form, the
   actor? Then it is the server's, in Rust, thin, over the facade.

## The laptop's sharp edges

- Relinking the extension while a server has it mapped makes every
  later load die with `Code Signature Invalid` (exit 137, a suite
  that finishes in 0 s): stop the server, remove the dylib, relink.
- DuckDB is compiled into every binary (libduckdb-sys `bundled`,
  about three minutes once per profile, cached in `target/`); the
  extension binds through the C API table the host hands it at load,
  so no symbol of the host is involved and no library file travels.
- The kits are loaded from the sibling checkout and from `kits/` at
  runtime, so a kit edit needs no rebuild; a C++ change does
  (`GEN=ninja make release` in `../gloss`).
- The door wraps a DuckDB refusal in `C Data interface error: …`; the
  text after it is the engine's.
