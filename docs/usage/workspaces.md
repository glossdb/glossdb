# Workspaces and datasets

A workspace is one DuckLake: the data, and the catalog of everything
declared and annotated over it. A dataset is one working set inside it,
such as the tables and metrics of one analysis.

## Create a dataset

```glossql
DECLARE DATASET fin SET (purpose: 'working-capital analysis over ERP and CRM exports');
USE fin;
```

A dataset is a schema of the lake. Its tables are loaded from sources
([loading data](loading-data.md)), and every load is one snapshot that
gives the table a new version. The `imports` table keeps one row per
load.

Three names are reserved: `glossql` (the catalog's own schema), and
`mcp` and `assets` (paths the server answers beside the datasets).
`DECLARE DATASET` refuses each.

## Choose the dataset for a call

`USE` sets the dataset for the statements after it in the call. The
dataset's own interfaces (`/<dataset>/mcp`, `/<dataset>/query`,
`/<dataset>/app`) open every call on that dataset, so a caller there
needs no `USE`.

Names resolve like this:

- `table.column` resolves against the dataset in use;
  `dataset.table.column` always works.
- A name that is both a dataset and a table of the dataset in use is
  the table: the nearer scope wins. Reach the other dataset under its
  own `USE`.
- A table named like its own dataset is reached by its columns only;
  the bare name is the dataset.
- An app part is `<app>.<part>` under the dataset in use, so an app
  named like its dataset keeps its parts.

The actor (an agent or a person) comes with the connection; no
statement names it. Two actors on one dataset hold two sessions, and
so does one actor on two datasets.

## How the catalog keeps history

Every declaration, annotation, measurement and load is a row in the
catalog, written beside the lake's own tables. Writes append; nothing
is deleted.

- **The newest value wins at read.** The current value for an asset
  and a property is the newest row per kind of actor. Annotating again
  appends a row that wins; the old row stays as history.
- **Annotations know their data version.** Every annotation stores the
  snapshot of its table at write time. When the column it describes is
  re-derived, retyped or dropped, or its table loses a column, the
  annotation is still served and marked `stale`. New rows of the same
  shape age nothing.

## What is shared across datasets

Properties (aspects) are declared once for the workspace. A function
is scoped to one dataset (`FOR fin`) or to all (`GLOBAL`). Annotations
belong to one dataset, with one exception: a property declared
`ON SOURCE` annotates a source, and sources belong to the workspace, so
what one dataset records about a source system every other dataset
reads ([source conventions](loading-data.md#record-source-conventions)).
