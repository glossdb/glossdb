# The substrate

glossql is built on DuckDB. The gloss extension owns the language and
the record; DuckLake owns the lake; this repository owns the doors.
Nothing here re-implements what the engine does: a read is SQL the
engine plans, a kit is SQL the engine runs, a measurement is a SQL
body the engine executes.

## What the extension owns

- **The grammar.** The statements of the language, parsed by the
  extension's grammar on DuckDB's parser: declarations, `GLOSS`,
  `IMPORT`, `PROBE`, the reads `GLOSSARY()` and `ATTEST()`, a
  measurement over a subject.
- **The store and the record read.** The relations as tables in the
  lake's catalog, served as `ws.glossql.*`; the collapse of slots, the
  witnesses and detectors, the stale rule, the record read kept per
  store version ([store](store.md)).
- **Subjects.** A dataset, a table, a column, a relationship, a source,
  and a view with its columns: a metric's grounding stands as a view
  under its name, and its columns are subjects like a table's.
- **The lineage of views** (`gloss_views_lineage`), **the cells of a
  dataset** (`dataset_cells`, every cell of its tables or its views as
  rows, which the quality screens read), **a view kept per store
  version** (`gloss_kept_view`), and **the service call**
  (`gloss_service(route, body)`, JSON each way, with a soft form that
  answers a refusal as a value).
- **The kits' loader.** `FROM gloss_kit('<file>')` runs a kit's
  statements in order.

## What the server owns

- **The plane.** One DuckDB instance per process. At open it loads
  the extension and the lake's extensions, attaches the lake, declares
  the record's reads, runs the kits, declares the door's reads and
  composes the `next` read from every kit's routes.
- **A channel per call.** One connection: the grammar on, the actor
  set as session variables the extension reads, the dataset in use,
  a search path of the dataset's schema and the store's. No door keeps
  a cursor.
- **The doors.** The MCP door, the Arrow door, the app door and the
  docket, the pages.

## The rules the substrate imposes

- **Every DuckDB call is synchronous.** Each runs on the blocking
  pool and hands its rows back as Arrow batches; nothing of the
  engine's runs on the async runtime's threads.
- **A read never writes.** The record read and the kept views are
  computed once per store version and served from the object cache;
  a write moves the version.
- **A kit is content.** A new measurement, read or route is a
  statement in a kit, loaded at open, never a change to the server.
- **The extension is pinned.** `crates/duck/gloss.ref` names the
  commit of the extension the build carries; the DuckDB release is
  the one the Rust side links, and the extension is built against the
  same one.
