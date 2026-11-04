# Storage

A workspace is a DuckLake: a catalog and the files it names. The
catalog is the workspace directory's `catalog.ducklake` on a laptop,
or the Postgres database `GLOSSDB_CATALOG_SQL` names in a deployment.
It holds two things side by side: the lake's own metadata — every
landed table, its versions, each version's files — and the record,
every relation the language declares as a table of rows
([store](store.md)). The files are parquet under the warehouse: the
directory beside the catalog, or the object-store location
`GLOSSDB_WAREHOUSE` names.

## The lake

The catalog's tables are the DuckLake specification's, so any DuckLake
reader attaches to the same catalog and reads the same files.

- **A dataset is a schema.** `DECLARE DATASET` makes it; its settings
  are a row of the record's `datasets` relation.
- **A landed table is a DuckLake table.** A recipe lands it, typed by
  the recipe; `IMPORT` runs the recipe again and replaces the table in
  one commit. A landing's facts — what it read, what it dropped, the
  version it made — are one row of the `imports` relation; the recipe
  behind a table is a row of `recipes`.
- **A version is a snapshot.** Every write is one transaction that
  makes a snapshot; a table's version is the snapshot that last
  changed it. A gloss on a column stores the snapshot it was written
  at, and the stale rule compares it with the column's own history.
- **A grounding is a view.** The serving grounding of each metric
  stands in the dataset's schema as a view under the metric's name;
  a superseding grounding replaces it, a stop ends it. The engine
  keeps a view's rows once per store version.

## Reads

A statement reads the lake at its snapshot through the engine's own
parquet scan, with the engine's pruning. A dataset-qualified name
resolves through the attached lake; a bound channel's `USE` puts the
dataset's schema first, and the record's views in the lake's `main`
schema are on every search path, so `FROM glossary` reads bare from
any dataset in use.

## The warehouse

Files are written by the lake under `<warehouse>/<dataset>/<table>/`.
A remote warehouse is reached through the engine's `httpfs` extension,
`s3://` and `gs://`, with the credentials the engine's secrets hold;
the local directory stays the laptop's shape.
