# Storage

A workspace is a DuckLake: a catalog and the files it names.

- **The catalog** is `catalog.ducklake` in the workspace directory on a
  laptop, or the Postgres database `GLOSSDB_CATALOG_SQL` names in a
  deployment. It holds two things side by side: the lake's own
  metadata (every loaded table, its versions, each version's files) and
  glossql's catalog, every relation the language declares, as tables
  of rows ([the catalog](catalog.md)).
- **The files** are Parquet under the warehouse: the directory beside
  the catalog, or the object-store location `GLOSSDB_WAREHOUSE` names.

## The lake

The catalog's tables follow the DuckLake specification, so any DuckLake
reader can attach the same catalog and read the same files.

- **A dataset is a schema.** `DECLARE DATASET` creates it; its settings
  are a row of the `datasets` relation.
- **A loaded table is a DuckLake table.** A load query loads it, typed
  by the load query. `IMPORT` runs the load query again and replaces the
  table in one commit. What a load read, what it dropped and the
  version it made are one row of the `imports` relation; the load query
  behind a table is a row of `recipes`.
- **A version is a snapshot.** Every write is one transaction that makes
  a snapshot; a table's version is the snapshot that last changed it.
  An annotation on a column stores the snapshot it was written at, and
  the stale rule compares it with the column's own history.
- **A metric definition is a view.** The current definition of each
  metric is a view in the dataset's schema under the metric's name. A
  newer definition replaces it; a stop removes it. The engine keeps a
  view's rows once per catalog version.

## Reads

A statement reads the lake at its snapshot through the engine's own
Parquet scan, with the engine's pruning. A dataset-qualified name
resolves through the attached lake. A call's `USE` puts the dataset's
schema first, and the catalog's views in the lake's `main` schema are on
every search path, so `FROM glossary` works bare from any dataset in
use.

## The warehouse

The lake writes files under `<warehouse>/<dataset>/<table>/`. A remote
warehouse (`s3://`, `gs://`) is reached through the engine's `httpfs`
extension, with the credentials held in the engine's secrets. The local
directory is the laptop setup.
