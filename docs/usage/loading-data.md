# Loading data

A source says where data comes from. A load query (`RECIPE`) turns
what the source holds into a typed table of a dataset. The loaded table
is the typed table: the load query carries the casts, and you preview
it first to write them.

## Declare a source

```glossql
DECLARE SOURCE erp_export SET (type: parquet, location: 'lake/erp');
DECLARE SOURCE crm SET (type: relational_db, location: 'postgres://crm.internal/prod', via: crm_prod);
```

- `type` is `relational_db`, `parquet`, `csv` or `json`; any other
  value is refused.
- For a file source, `location` is the root that paths in the load
  query resolve under: a directory, or an object store prefix
  (`s3://bucket/prefix`, `gs://bucket/prefix`,
  `abfss://container@account.dfs.core.windows.net/prefix`). The
  server reads it with its own rights (its environment, or the
  platform's managed identity); a location never carries a
  credential. Secrets are DuckDB's `CREATE SECRET`.
- For a relational source, the source is a database DuckDB has
  attached (Postgres, MySQL, SQLite, DuckDB), and the load query runs
  over it in DuckDB SQL; the scanner pushes down what it can. `via`
  names the attached database.
- A file type describes the export; it does not limit the load query.
  The query names its own reader (`read_parquet`, `read_csv`,
  `read_json`), and all three resolve under the location.

## Preview, then load

List what a file source holds with `PREVIEW`:
`PREVIEW erp_export AS $$SELECT file FROM glob('*')$$` lists the files
under the location, `glob('**')` the subdirectories too
([the sources' files](../reference/reads.md)).

`PREVIEW source AS $$sql$$` runs SQL at the source and loads nothing.
The result always carries its schema, so a `LIMIT 0` preview of the
final SQL shows exactly the columns and types the load will create. At
a file source a table is a file: a query that names a plain table is
refused, with the source's files and the `read_*` call that reads one.

```glossql
PREVIEW erp_export AS $$SELECT count(*) AS n, count(p_rec) AS reconciled_parsed
FROM (SELECT try_cast(reconciled AS BOOLEAN) AS p_rec
      FROM read_csv('bank_transactions.csv'))$$;

DECLARE RECIPE bank_transactions ON fin_ap FROM erp_export AS $$
  SELECT txn_id, try_cast(account_id AS BIGINT) AS account_id,
         try_cast("date" AS DATE) AS date,
         try_cast(amount AS DOUBLE) AS amount, currency, reference,
         counterparty, try_cast(reconciled AS BOOLEAN) AS reconciled,
         payment_id
  FROM read_csv('bank_transactions.csv')$$;
```

Declaring the load query loads the table. The default query is
`SELECT *`. Use `try_cast` and `try_strptime` so a bad value becomes
NULL instead of failing the load.

### Keyed tables

A load query may name the table's key, `SET (key: order_id)` before
`AS`: one column of its result, or a comma-separated list.

- A keyed table merges on every load: rows with a key already in the
  table replace those rows, and every other row stays.
- An unkeyed table is replaced by the result.
- The result must carry each key once. A result with a duplicate key
  is refused, naming the key; say which row wins in the query, for
  example with a `QUALIFY` over the file name when a glob reads a base
  file and a changes file.
- A key the query does not produce is refused at the declaration.

Merging suits a large source whose owner exposes only what changed: a
view of the rows changed in a window, read as it is. A row the source
no longer returns is not removed by the merge. A source that deletes
rows exposes the deletes as rows with a flag, and the load query
carries the flag as a column.

### Rows the reader rejects

Each load records `dropped_rows_count`, in the statement's result and
in `imports`. It counts the rows the CSV reader rejected when the load
query stores its rejects (`store_rejects`), is NULL when the query
ignores errors without storing them, and is 0 otherwise. Which rows
they were is the reader's `reject_errors` table, at the source.

The load query holds the typing: casts, date formats and the source's
null markers. Excluding rows, recoding values or dropping duplicates is
a decision, not typing. It goes in a derived view the metrics read
from (`x-kind: "relation"`), and each metric records it as an
assumption a person reviews ([metrics](metrics.md)). Nothing finds
placeholder values for you: `column_profile()` shows the candidates.

## Correct a load query

A load query's identity is its content: the SQL and the schema it
produces. Declaring the same query again does nothing. Declaring a
changed one replaces it and loads the table again, in one snapshot.

Annotations stay. Each ages by its own column: an annotation on a
column the new query re-derived, retyped or dropped reads `stale`; one
on an unchanged column stays `current`; an annotation on the table
ages when any of its columns did. This is how you correct a source
problem: change the load query, never the data.

## Refresh a table

`IMPORT <table>` runs the load query again and loads what the source
holds now, in one snapshot: a keyed table merges, an unkeyed table is
replaced. The table's history, its loads in `imports` and its
annotations stay. Nothing watches a source; a schedule or an agent
sends the statement.

Every load is a DuckLake snapshot, so earlier versions stay readable
(`AT (VERSION => n)`).

## Record source conventions

What you learn about a source system, such as its date formats, sign
conventions or naming quirks, belongs to the source, not to one
dataset. A property declared `AS FACT ON SOURCE` annotates the source,
and every dataset in the workspace reads it:

```glossql
DECLARE ASPECT conventions WITH $${"type": "object"}$$ AS FACT ON SOURCE;

GLOSS conventions ON erp_export AS $${
  "dates": "ISO YYYY-MM-DD throughout; try_cast(x AS DATE) suffices",
  "currency": "single-currency USD on every monetary table",
  "sign": "journal net_amount = debit - credit (debit-positive), an exact identity"
}$$;
```

The next dataset from the same system reads these conventions before
its first preview, and adds to them by annotating again. Evidence
about one dataset, such as orphaned rows or a table's grain, stays on
that dataset's tables: record at source level only what the next
export will carry too.

The `kpi` kit declares `conventions` already; declare it yourself only
in a workspace without the kit.
