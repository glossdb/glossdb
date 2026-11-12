# Connect and load

A source says where data comes from. A load query brings one table
from a source into a dataset. Each load is a snapshot of the lake.
A load copies the data into the lake. Reading a lake or a catalog in
place, without a copy, is planned.

## Declare a source and a dataset

```glossql
DECLARE SOURCE fleet_export SET (type: parquet, location: '/data/fleet');
DECLARE DATASET logistics SET (purpose: 'deliveries: what was promised, what arrived, how late');
USE logistics;
```

- `type` is `csv`, `parquet`, `json` or `relational_db`.
- For a file source, `location` is the directory the load query's
  paths resolve under.
- For `relational_db`, `location` is the name of a database attached
  to the engine. `ATTACH` is open to the actors `GLOSSDB_ROOT` names
  ([configuration](../reference/configuration.md)). The load query
  then runs in that database.
- A dataset is a schema of the lake. `DECLARE DATASET` is sent at
  `/mcp`; `USE` binds the statements after it for one call.

## Look before loading

A dry run (`PREVIEW`) runs SQL at the source and loads nothing.

```glossql
PREVIEW fleet_export AS $$SELECT file FROM glob('**') ORDER BY file$$;
PREVIEW fleet_export AS $$SELECT * FROM read_parquet('deliveries/*.parquet') LIMIT 0$$;
```

`LIMIT 0` returns each column with its type.

## Write the load query

```glossql
DECLARE RECIPE deliveries ON logistics FROM fleet_export AS $$
  SELECT delivery_id, depot, promised_at, arrived_at, parcels
  FROM read_parquet('deliveries/*.parquet')$$;
```

The table is named after the load query. Name the columns: a schema
change at the source then fails at the next load.

**Typed sources load as they are.** Parquet files and database tables
carry types.

**A CSV file gets one standard reader configuration**, and the load
query carries the casts:

```glossql
DECLARE RECIPE depots ON logistics FROM fleet_export AS $$
  SELECT trim(depot) AS depot,
         try_cast(trim(capacity) AS INTEGER) AS capacity,
         try_strptime(opened, '%d.%m.%Y')::DATE AS opened
  FROM read_csv('depots.csv', all_varchar = true,
                nullstr = null_markers(), store_rejects = true)$$;
```

- `all_varchar` reads each cell as text, so a leading zero and a date
  format reach your cast unchanged.
- `null_markers()` lists the strings an export writes for no value
  (`NA`, `N/A`, `#N/A`, `--`, `MISSING` and others). `SELECT
  null_markers()` shows the list. Pass your own list where one of them
  is a real value.
- `store_rejects` keeps a line the reader cannot parse out of the
  table and counts it as dropped.
- `try_strptime` takes one format or a list and uses the first that
  parses.
- A cast written directly on a CSV column, `try_cast(capacity AS
  INTEGER)`, is applied by the reader: a line whose cell fails it is
  dropped and counted. A cast over an expression, `try_cast(trim(capacity)
  AS INTEGER)`, keeps the row and stores NULL.

## Read the result

A load answers with its counts:

```
loaded logistics.deliveries: 48210 rows, 0 dropped (new)
```

`imports` keeps one row per load: `table_name`, `mode` (`replace` or
`merge`), `rows`, `dropped_rows_count`, `lineage` (each column's
expression over the source's columns), `snapshot_id`, `imported_at`.

```sql
SELECT table_name, mode, rows, dropped_rows_count, imported_at FROM imports;
```

## Load again

```glossql
IMPORT deliveries;
```

`IMPORT` runs the table's load query again over the source as it is
now. Nothing watches a source: a schedule or an agent sends the
statement.

- Without a key, the result replaces the table.
- With a key, `DECLARE RECIPE deliveries ON logistics FROM
  fleet_export SET (key: delivery_id) AS …`, the result merges into
  the table by that key. A result that carries a key twice is refused.
- Declaring a load query again with changed SQL replaces it and loads
  again. Unchanged, it does nothing.

Annotations stay across loads. An annotation on a column the new load
redefined, retyped or dropped reads `stale`
([describe](describe.md#states)). After a load the server runs the
built-in tests of each metric that reads the table
([test](test.md)), and `next` says what the load changed: the row
counts and the columns whose profile moved.

## What the source's next export will also carry

Annotate the source. A source belongs to the workspace, so each
dataset that loads from it reads the annotation.

```glossql
GLOSS conventions ON fleet_export AS $${
  "placeholder_date": "01.01.1900 means unset",
  "depot_codes": "three letters, upper case"
}$$;
```

## A change to a load query that a person approved

A person records an approved change as a `recipe_change` annotation
on the table, with `table`, `sql` and `reason`. It shows in `next`
as an `integrate` row until a load of that table is newer than the
approval.

## Plain SQL writes

`CREATE TABLE … AS`, `INSERT`, `DELETE`, `COPY` and `DROP TABLE` run
as DuckDB runs them. A table made this way has no load query: no row
in `imports` and no `IMPORT`. Use a load query for data that arrives
again.
