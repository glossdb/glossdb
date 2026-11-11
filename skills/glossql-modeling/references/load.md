# Loading: sources, load queries, CSV files, dropped rows

Read before the first `PREVIEW` or `DECLARE RECIPE`.

## Source and dataset

A dataset is the working set for one topic. Its `purpose` is the only
setting:

```glossql
DECLARE DATASET fleet SET (purpose: 'sensor readings per vehicle, for maintenance planning');
```

A source is a root: a directory on the server's machine, an
object-store URL, or a database. `type` is `csv`, `parquet`, `json`
or `relational_db`. File paths in a load query resolve under the
root, and the reader function in the SQL picks the format. A database
source takes `via`, the name of a secret the engine holds;
credentials do not go in statements, and it runs the load query's SQL
itself, in its own dialect.

```glossql
DECLARE SOURCE workshop SET (type: relational_db, location: 'postgres://workshop.internal/prod', via: workshop_prod);
```

What you learn about a source system (a placeholder date, how ids
are written) is annotated on the source as `conventions`, a free JSON
object, and is read in every dataset that loads from it: `GLOSS
conventions ON telemetry AS $${"placeholder_date": "1900-01-01 means
not set"}$$`.

## Look before you load

List the files (`glob('**')` includes subdirectories), then check the
schema with `LIMIT 0`. A preview of rows leaves null fields out, so a
column that is null in the sample does not show there.

```glossql
PREVIEW telemetry AS $$SELECT file FROM glob('*') ORDER BY file$$;
PREVIEW telemetry AS $$SELECT * FROM read_parquet('readings/*.parquet') LIMIT 0$$;
```

## The load query

A load query (`DECLARE RECIPE`) is the SQL that produces the table.
Declaring it loads the table, typed as the SQL types it.

- **Name the columns.** With `SELECT *` a schema change in the source
  shows up later, somewhere downstream. With named columns it fails at
  the next load.
- **Load what the job needs.** Each loaded column that a view reads
  asks for annotations.
- **Typing goes in the load query; decisions do not.** A cast, a
  trim, a null marker, a date format is typing. Leaving rows out,
  recoding a value or dropping a duplicate is a decision: put it in a
  table view and state it as an assumption, so a person sees it.
- **A key merges.** `SET (key: reading_id)` names the table's key (one
  column, or a comma-separated list). Each load then merges by it. The
  result must carry each key once, or the load is refused and names a
  key. Without a key each load replaces the table.
- **Declared again with other SQL**, the load query replaces the old
  one and loads the table again. The annotations stay; those on a
  column the new load changed read `stale`.
- `IMPORT readings;` loads the table again from the source as it is
  now. `DROP TABLE` is refused while the table holds data or
  annotations.

```glossql
DECLARE RECIPE readings ON fleet FROM telemetry SET (key: reading_id) AS $$
  SELECT reading_id, vehicle_id, measured_at, engine_temp_c, odometer_km
  FROM read_parquet('readings/*.parquet')$$;
```

The acknowledgement says what happened: `loaded fleet.readings: 48210
rows, 0 dropped (new)`. The `imports` table keeps each load:

```sql
SELECT table_name, mode, rows, dropped_rows_count, imported_at FROM imports ORDER BY seq DESC
```

## CSV files

A CSV has no types. Give its reader the standard options, and write
the casts in the SELECT:

```glossql
DECLARE RECIPE bookings ON fleet FROM workshop_files AS $$
  SELECT nullif(trim(booking_id), '') AS booking_id,
         trim(vehicle_id) AS vehicle_id,
         try_strptime(trim(booked_for), '%d.%m.%Y')::DATE AS booked_for,
         try_cast(trim(hours) AS DOUBLE) AS hours
  FROM read_csv('bookings.csv', all_varchar = true,
                nullstr = null_markers(), store_rejects = true)$$;
```

- `all_varchar = true` reads every cell as text. A leading zero in an
  id and a date's format reach your cast unchanged.
- `nullstr = null_markers()` reads the strings an export writes for
  no value as NULL: `NA`, `N/A`, `n/a`, `NULL`, `--`, `MISSING`,
  `#N/A` and others. `SELECT null_markers()` lists them. Where one of
  them is a real value in this file, pass your own list.
- `store_rejects = true` keeps a line the reader cannot parse out of
  the table and counts it in `dropped`.
- **Wrap the column before you cast it.** A cast written directly on
  a CSV column, `try_cast(hours AS DOUBLE)`, is applied by the reader:
  a cell that does not convert drops the whole row, counted in
  `dropped`. A cast over an expression, `try_cast(trim(hours) AS
  DOUBLE)`, keeps the row and stores NULL. Use the second form unless
  the row should go.
- The reader does not trim. A padded ` 007` is another value than
  `007`, and ` n/a ` is not a null marker. Trim ids and text in the
  SELECT.
- `try_strptime(x, ['%Y-%m-%d', '%d/%m/%Y'])` takes a list and uses
  the first format that parses. The order decides ambiguous rows:
  `02/03/2025` is March 2nd under `%d/%m/%Y`. Where two formats both
  parse and it matters, count the rows and state the reading as an
  assumption.

**When rows are dropped**, find them at the source before you go on.
Read the column as text and look at what does not convert:

```glossql
PREVIEW workshop_files AS $$SELECT hours, count(*) AS n
  FROM read_csv('bookings.csv', all_varchar = true)
  WHERE try_cast(trim(hours) AS DOUBLE) IS NULL GROUP BY 1 ORDER BY n DESC$$;
```

## After the load

Measure what you loaded: `SELECT column_profile() FROM bookings.hours`
gives the share of nulls, distinct values, minimum and maximum;
`temporal()` on a date column its grain, span and gaps. Write what is
true of this load into `meaning` on the table or column. What must
stay true is a test (`tests.md`).
