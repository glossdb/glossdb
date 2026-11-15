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
expression over the source's columns), `snapshot_id`, `imported_at`,
`source_rows` (the rows the load query returned) and `changed_rows`
(the rows the load inserted, updated or removed against the table
before it).

```sql
SELECT table_name, mode, rows, source_rows, changed_rows, dropped_rows_count, imported_at FROM imports;
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

## A full load or a keyed load

Choose by what the source sends.

| The source sends | Load | What it costs |
|---|---|---|
| its complete state each time, or you do not know | without a key: the table is the file | each load writes the whole table again, changed or not. Measured: 1,000,000 identical rows of ten columns write 89 MB of Parquet |
| only new and changed rows | with a key (`SET (key: …)`) | a load writes only the rows that changed; identical rows write nothing. A row the source deletes stays in the table |

State what the source sends on the table. A person can confirm or
correct it:

```glossql
GLOSS delivery ON logistics.deliveries AS $${"value": "incremental", "basis": "the export holds the deliveries changed since the last run"}$$;
```

`load_modes()` holds the newest load of each table against the load
before it. `next` lists two cases as `integrate` rows:

- **`keys missing`**: a keyed load whose file carried at least 90% of
  the keys the table held, and missed some. The source likely sends
  its complete state, so rows deleted at the source stay in the table.
  The fix loads without the key. A `must` where `delivery` is `full`,
  a `should` otherwise.
- **`unchanged`**: a load without a key of at least 100,000 rows that
  changed at most 1% of them. The row names the key to merge by: the
  load query's key, the table's `entity` grain, else a column whose
  profile is filled and unique. A `should`, and only where `delivery`
  is not `full`.

The numbers come from public data: a complete monthly file of EIA-860M
carries 99.84% to 99.99% of the generators of the month before; a
yearly filing of FERC Form 1 carries 3.7% to 13.2% of the rows filed
before it.

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
