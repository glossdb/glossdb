# Loading — read before the first PREVIEW or DECLARE RECIPE

## Agree the topic first

A dataset has a topic: on-time delivery, capacity, cost control. The
topic decides which tables to load, which metrics to propose and which
questions matter. Propose one from what you can see, let the person
shape it, then declare it:

```glossql
DECLARE DATASET ops SET (purpose: 'service delivery — what gets done, how fast, and where it stalls');
```

Then propose the metrics the topic implies, the hard ones included (an
end-to-end cycle time, real utilization). The person prunes and adds.
Scope questions are cheap here: "cycle time from which timestamp?"
costs one sentence now and a wrong dashboard later. A metric the data
cannot serve is a finding: name what is missing and which tables would
close it.

Do this in chat. The topic, the metric list and how much to load are
conversation. The review queue only asks about assumptions that
already exist.

## Load what the topic needs

A dataset is a working set for its topic, not a copy of the export.
Load the tables the metrics need, select only the columns you will
use, and filter wide tables in the load query's WHERE. Leaving
something out costs one more `DECLARE RECIPE` later. Loading
everything costs on every read: more columns to annotate, more
required annotations, slower relationship searches (they scale with
the number of column pairs).

**Read the source's conventions before you preview.** Annotations on a
source are served in every dataset, so what was learned earlier about
this system (placeholder dates, formats, key spellings) is already
there:

```glossql
SELECT value FROM GLOSSARY(erp_export) WHERE aspect = 'conventions';
```

Write back what you learn:

```glossql
GLOSS conventions ON erp_export AS $${
  "placeholder_date": "1900-01-01 stands for unset",
  "timestamp_format": "%b %e %Y %I:%M%p, month names mixed-language"
}$$;
```

Only what the next export from that system will also carry goes on the
source. What is true of this load goes on the dataset's tables and
columns.

**List the files before naming one.** `glob('**')` lists
subdirectories too:

```glossql
PREVIEW erp_export AS $$SELECT file FROM glob('*') ORDER BY file$$;
```

**Check the schema with `LIMIT 0`, per file, before writing a load
query.** A zero-row preview returns every column name and type. A
preview of rows omits null fields, so a column that is null in your
sample is missing, and a missed join key is a missed relationship.

```glossql
PREVIEW erp_export AS $$SELECT order_id,
       try_cast(amount AS DOUBLE) AS amount,
       try_strptime(order_date, '%d.%m.%Y')::DATE AS order_date
FROM read_parquet('orders/*.parquet') LIMIT 0$$;
```

**Name the columns; never `SELECT *`.** With named columns, a schema
change in the source fails at the next load, where you can fix it.
With a star it fails later, somewhere downstream.

**You write the casts.** The load query carries the casts and the
column choice; nothing types the data for you. A failed `try_*` cast
stores NULL in a kept row.

```glossql
DECLARE RECIPE orders ON ops FROM erp_export AS $$
  SELECT order_id,
         try_cast(amount AS DOUBLE) AS amount,
         try_strptime(order_date, '%d.%m.%Y')::DATE AS order_date
  FROM read_parquet('orders/*.parquet')$$;
```

**Dates past 2262-04-11 are not periods.** A year beyond that is a
token the source wrote, not a date. `try_cast(x AS TIMESTAMP)` stores
it as NULL and the cast report counts it. `try_strptime` keeps it, and
the expected-ranges run then skips every metric on that column, with
the reason.

**One date column may hold several formats.** `try_strptime` takes a
list and uses the first format that parses:

```glossql
PREVIEW erp_export AS $$SELECT
  try_strptime(paid, ['%Y-%m-%d', '%d/%m/%Y', '%m/%d/%Y', '%d-%b-%y'])::DATE AS paid
FROM read_csv('payments.csv') LIMIT 5$$;
```

The order decides ambiguous rows: `02/03/2025` is March 2nd under
`%d/%m/%Y` and February 3rd under `%m/%d/%Y`. Put the unambiguous
formats first. Where two readings both parse and the count matters,
measure it (count the rows impossible under each) and disclose the
rest as a keyed assumption, with the number of rows no evidence could
decide.

**Read the cast report.** The load's result lists, for every `try_*`,
how many cells the cast set to NULL and their most frequent values.
A repeated `\N` or `n/a` is a null marker: add `NULLIF` before the
cast and declare the load query again; it replaces the old one and
loads again. A scattered tail may be bad data worth a `meaning`
annotation. A reload keeps the annotations. Run the measurements again
for the columns the new load query changed.

**A relational source runs your SQL itself**, in its own dialect.
SQLite has no date type: `CAST(date(x) AS DATE)` stores `2010` for
`'2010-12-27'`. Load such a column as text, cast it when you read, and
say so in the column's `meaning`. Run `DESCRIBE <table>` right after a
load: a number loaded as text shows there.

## Measure the defects

Nobody gives you a list of the data's defects. You find them. Measure
first, decide second, and write the decision where the next reader
looks.

- **Measure.** Which table or column, what share of rows, since when.
  The cast report at load; `column_profile()` for nulls, distinct
  counts and top values; `temporal()` for gaps;
  `relationship_coherence()` for orphans and children dated before
  their parent; `detect_derivations()` for an identity that breaks. A
  finding is a number.
- **Only typing goes in the load query.** A null marker, a cast, a
  date format is typing. Excluding a row, recoding a value, turning a
  sentinel to NULL or dropping a duplicate is a decision, and inside a
  load query nobody sees it. Put it in one derived relation the
  metrics read (`x-kind: "relation"`), and disclose it on each metric
  as a keyed `scope` or `convention` assumption below 1.0, so the
  review asks it.
- **Write it down.** What the next export will also carry: in
  `conventions` on the source. What is true of this load: in `meaning`
  on the column or table. What must stay watched: a test, with the
  expectation set at the rate you measured today. `TESTS()` is green
  now and turns red when the source drifts
  (`references/validate.md`). A person sees the test; a finding
  without one is known only to you.

Whether a metric is served on that data or stopped is decided in its
definition: `references/ground.md`.
