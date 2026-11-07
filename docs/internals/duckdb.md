# Building on DuckDB

glossdb is built on DuckDB. The glossql extension owns the language and
the catalog; DuckLake owns the lake; the server owns the interfaces.
Nothing in the server re-implements what the engine does: a read is
SQL the engine plans, a kit is SQL the engine runs, and a measurement
is a SQL body the engine executes.

## What the extension owns

- **The grammar.** The language's statements, parsed by the extension's
  grammar on DuckDB's parser: declarations, `GLOSS`, `IMPORT`, `PREVIEW`,
  the reads `GLOSSARY()` and `TESTS()`, and a measurement over an
  asset.
- **The catalog and its reads.** The relations as tables in the lake's
  catalog, served as views in `ws.main`; the newest value per author,
  tests and detectors, the stale rule, and the catalog reads kept per
  catalog version ([the catalog](catalog.md)).
- **Assets.** A dataset, a table, a column, a relationship, a source,
  and a view with its columns: a metric definition is a view under the
  metric's name, and its columns are assets like a table's.
- **Building blocks for kits:**
  - the lineage of views (`glossql_views_lineage`);
  - the cells of a dataset (`dataset_cells`): every cell of its tables
    or its views as rows, which the quality screens read;
  - a view kept per catalog version (`glossql_kept_view`);
  - the service call (`glossql_service(route, body)`), JSON both ways,
    with a soft form that returns a refusal as a value.
- **The kit loader.** `FROM glossql_kit('<file>')` runs a kit's
  statements in order.

## What the server owns

- **One engine.** One DuckDB instance per process. At open it loads the
  extension and the lake's extensions, attaches the lake, declares the
  catalog reads, runs the kits, declares the interfaces' reads, and
  composes the `next` read from every kit's steps.
- **A connection per call.** The grammar on, the actor set as session
  variables the extension reads, the dataset in use. The catalog reads
  work bare from any dataset, since the lake's `main` schema is on
  every search path. No interface keeps a cursor.
- **The interfaces.** MCP, the query endpoint, the console and the
  pages.

## Rules

- **Every DuckDB call is synchronous.** Each runs on the blocking pool
  and returns its rows as Arrow batches. No engine work runs on the
  async runtime's threads.
- **A read never writes.** The catalog reads and the kept views are
  computed once per catalog version and served from the object cache.
  A write moves the version.
- **A kit is content.** A new measurement, read or next step is a
  statement in a kit, loaded at open, never a change to the server.
- **The extension is pinned.** `crates/duck/glossql.ref` names the
  extension commit a build carries. The DuckDB release is the one the
  Rust side links, and the extension is built against the same one.
