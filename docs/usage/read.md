# Read the views

The layer holds tables, single values and metrics, each with its
description, its test results and its lineage. A view can be queried
once it is defined. People, agents and tools read the views in four
ways: SQL over an interface, files, the console, and the lake itself.

## Read a view

A view reads like a table, by name:

```sql
SELECT room_type, sum(nights) AS nights FROM stays.confirmed_bookings GROUP BY room_type;
```

```sql
FROM stays.room_count;
```

`fact_values()` returns each single value of the dataset as one row:
`metric`, `value`, `reason`.

## Read a metric's series

`metric_series()` returns each metric as cells: `metric`, `dimension`
(`''` for the total, else a slicing column), `member`, `period` (the
start of the period), `value`.

```sql
SELECT period, value FROM metric_series(view := 'booked_nights', grain := 'month')
WHERE dimension = '' ORDER BY period;
```

```sql
SELECT member, period, value FROM metric_series(view := 'booked_nights', grain := 'quarter')
WHERE dimension = 'room_type' ORDER BY period, member;
```

`view :=` reads that one metric's rows. Without it, the read serves
every metric of the dataset, and one metric whose additivity is not
stated refuses the whole read.

- Without `grain`, each metric is served at its own finest grain. With
  one (`minute` to `year`), each metric at or below it is served at
  that grain.
- The value combines by the metric's additivity: a sum, the period's
  last level, or the summed numerator over the summed denominator
  (`num`, `den`).
- An additive metric's empty periods are zero in the total.
- A dimension with more than 24 members serves its top 23 by weight
  and `other`.

## Ask before you trust a number

The description and the tests are one read away:

```sql
SELECT view, test, subject, state FROM view_tests() WHERE state <> 'green';
```

```sql
SELECT target_column, source_table, source_column, expression FROM column_mapping(for_view := 'booked_nights');
```

```glossql
SELECT subject, aspect, value, state FROM GLOSSARY(stays.booked_nights);
```

`column_mapping()` is the column lineage: each column a view serves,
the loaded column it comes from, the source system that table is
loaded from, and the expression between them. Lineage needs no work of its own. Each
load and each view definition records it.

## Over the interfaces

**MCP.** The `glossql` tool takes the reads above. A data read returns
at most `--row-cap` rows (default 200) and says `truncated`.

**The query endpoint.** `POST /<dataset>/query` with SQL as the body.
One read streams back as Arrow IPC
(`application/vnd.apache.arrow.stream`), without a row cap. Several
statements, or a write, answer in JSON.

```bash
curl -s -X POST http://127.0.0.1:8080/stays/query \
  -d "SELECT period, value FROM metric_series(view := 'booked_nights', grain := 'month') WHERE dimension = ''" \
  -o booked_nights.arrow
```

**Files.** `GET /<dataset>/app/export/<name>.csv` or `.parquet`
returns a table or a view whole. Parquet keeps the types.

Details of each: [interfaces](../reference/interfaces.md).

## From the lake

The workspace is a DuckLake. The loaded tables and the views are in
it, one schema per dataset, so a tool that opens the lake reads them
without the server. Measured with the DuckDB CLI and its `ducklake`
extension on a copy of a laptop workspace:

```sql
ATTACH 'ducklake:catalog.ducklake' AS lake (DATA_PATH 'warehouse', READ_ONLY);
SELECT * FROM lake.stays.confirmed_bookings;
```

The catalog tables are in the lake's catalog database as
`glossql_glossary`, `glossql_imports` and the other `glossql_*`
tables. The table functions (`metric_series()`, `view_tests()`,
`next`) are the server's; read them over an interface.

## In standard formats

```sql
SELECT document FROM semantic_model();
```

```sql
SELECT event FROM lineage_events();
```

- `semantic_model()` returns the dataset as one Apache Ossie document:
  each loaded table and each served metric with its fields, time and
  dimension columns, keys, relationships and descriptions. Units and a
  semi-additive or non-additive value go into `custom_extensions`.
- `lineage_events()` returns OpenLineage run events: one per load,
  with the column lineage the load recorded, and one per view, with
  the tables it scans and each column's source columns.

Measured on a dataset of two loaded tables, a table view and a
metric: the events of `lineage_events()`
validate against OpenLineage's JSON schema (spec 2-0-2, with the column
lineage facet 1-2-0). `semantic_model()` writes Ossie 0.3.0.dev0, a
draft whose schema still changes: its current schema expects the
extensions under another name than `custom_extensions`. Both reads
answer over the query endpoint.

## The console

`/<dataset>/app` opens the console, for people. `/` lists the
datasets.

| Section | Shows |
|---|---|
| Overview | coverage of the required annotations, open work, the model, the history, lineage |
| Catalog | each source, table, column and property with its annotations and measurements; tables and single values |
| Views | each metric: its series, slices, what moved, its assumptions and its SQL |
| Quality | test results worst first, each load with its dropped rows, required annotations nobody wrote |
| Review | the review queue and the decisions |
| Data | export as CSV or Parquet; a query pane for reads |

The console reads, with one write: a review decision. The server
computes the results a view needs after each write. Its overview
lists what must and what should be done, as `next` does.

## Data apps

A data app is a set of pages, SQL frames and chart specs over the
views, written as annotations by an agent or a person and served at
`/<dataset>/app/<name>`. Pages are markup; the server ships the
scripts. The parts and the tiles: [app authoring](../reference/apps.md).
