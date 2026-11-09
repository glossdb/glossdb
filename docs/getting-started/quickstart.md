# Quickstart

This walks one session from a company's raw exports to served metrics:
work orders and the sites they serve, as Parquet files. An agent on the
MCP interface usually sends these statements, and a person answers the
questions only a person can. Statements are glossql; plain SQL runs in
the same place.

## 1. Look around

A new workspace already holds the measurement functions and the
semantic layer's vocabulary (the KPI kit). Read before you declare:

```glossql
SELECT * FROM datasets;
SELECT name, kind FROM aspects;
```

## 2. Create a dataset

A dataset has a purpose, and the purpose decides later choices: which
tables to load, which metrics to define.

```glossql
DECLARE DATASET ops SET (purpose: 'service delivery — what gets done, how fast, and where it stalls');
USE ops;
```

Create datasets on the workspace path, `/mcp`. `USE` applies to the
statements after it, for the length of the call. From here on the
dataset has its own path, `/ops/mcp`, where every call opens on it and
no `USE` is needed.

## 3. Declare the source

A source names a root directory; file globs belong in the load query.
What you learn about a source system, such as placeholder dates or
odd formats, goes on the source, where every dataset reads it:

```glossql
DECLARE SOURCE erp_export SET (type: parquet, location: 'lake/erp');
GLOSS conventions ON erp_export AS $${
  "placeholder_date": "1900-01-01 stands for unset",
  "timestamp_format": "%b %e %Y %I:%M%p, month names mixed-language"
}$$;
```

## 4. Preview, then load

`PREVIEW` runs a query on the source without loading anything; with
`LIMIT 0` it returns the schema a load would create. The load query
carries the casts and names the columns, so the loaded table is typed.
A failed cast loads NULL, and the result reports how many cells each
`try_*` nulled, with the most common such values, so you can fix the
query (`NULLIF` before the cast) and declare it again.

```glossql
PREVIEW erp_export AS $$SELECT order_id,
       try_cast(duration_min AS DOUBLE) AS duration_min,
       try_strptime(completed_at, '%Y-%m-%d %H:%M:%S') AS completed_at
FROM read_parquet('work_orders/*.parquet') LIMIT 0$$;

DECLARE RECIPE work_orders ON ops FROM erp_export AS $$
  SELECT order_id, site_id, status,
         try_cast(duration_min AS DOUBLE) AS duration_min,
         try_strptime(completed_at, '%Y-%m-%d %H:%M:%S') AS completed_at
  FROM read_parquet('work_orders/*.parquet')$$;

DECLARE RECIPE sites ON ops FROM erp_export AS $$
  SELECT id, region, service_line
  FROM read_parquet('sites/*.parquet')$$;

DESCRIBE work_orders;
```

Load the tables the metrics need, and only the columns they use: a
dataset is a working set for its purpose, not a copy of the export.
More: [loading data](../usage/loading-data.md).

## 5. Describe each table

Say what one row is, whether the table holds facts or a dimension, the
columns that identify a row (check that `COUNT(*)` and
`COUNT(DISTINCT …)` agree), and the time column:

```glossql
GLOSS entity ON work_orders AS $${"value": "one site visit on a work order", "role": "fact",
  "grain": ["order_id"], "time_axis": "completed_at"}$$;
```

## 6. Measure

The shipped functions answer what statistics can. A measurement is
stored with the versions of what it read, and served again until that
data changes:

```glossql
SELECT column_profile(), outlier_profile() FROM ops.work_orders.duration_min;
SELECT temporal() FROM ops.work_orders.completed_at;
```

Discovery functions propose candidates with evidence, not conclusions.
Deciding what a measurement means is your job, or the agent's.

## 7. Declare the joins

`detect_relationships` proposes joins; anti-joins in both directions
decide. Orphans that are exactly a business population confirm a join;
random misses argue against it. Record the decision on the join:

```glossql
DECLARE RELATIONSHIP work_orders.site_id -> sites.id;
GLOSS meaning ON work_orders.site_id -> sites.id AS
  $${"value": "each order serves one site; the orphans are the cancelled orders, never dispatched"}$$;
```

Before you trust a join, check that it keeps the row count. If the
counts differ, the join multiplies every aggregate built on it:

```sql
SELECT count(*) FROM work_orders;
SELECT count(*) FROM work_orders w JOIN sites s ON w.site_id = s.id;
```

More: [relationships](../usage/relationships.md).

## 8. Describe the columns

Start with each column's role; what else a column must carry follows
from it. A measure's additivity (`behavior`: stock or flow) says how
the number combines over periods; read it off the rows, not the name.
Where a declared join reaches an event table, `SELECT
behavior_evidence() FROM <table>.<column>` measures it first: the level
reconciled against the movements.

```glossql
GLOSS meaning ON work_orders.duration_min AS $${"value": "on-site working time per visit, in minutes"}$$;
GLOSS role ON work_orders.duration_min AS $${"value": "measure"}$$;
GLOSS behavior ON work_orders.duration_min AS $${"value": "flow"}$$;
GLOSS unit ON work_orders.duration_min AS $${"value": "minutes"}$$;
```

More: [describing data](../usage/describing-data.md).

## 9. Define a metric

Declare one view aspect (`AS VIEW`) per metric. The business definition,
meaning, unit and owner, goes in the `definitions` annotation, where a
correction is stored with its author and time. The metric definition is
SQL at row grain, without GROUP BY, with mechanics as SQL comments and
judgment as assumptions. Every assumption carries a `key`, which review
decisions refer to.

```glossql
DECLARE ASPECT throughput WITH $${"title": "Throughput", "x-kind": "measure"}$$ AS VIEW;

GLOSS definitions ON ops AS $${"definitions": {
  "throughput": {"meaning": "work completed and accepted; counted at completion date",
                 "unit": "hours", "owner": "Operations", "source": "KPI handbook v3 §2"}
}}$$;

GLOSS throughput ON ops AS $${
  "sql": "-- completed work: hours per closed order, at completion date, with its judged axes\nSELECT w.completed_at AS date, w.duration_min / 60.0 AS value, s.region, s.service_line FROM work_orders w JOIN sites s ON w.site_id = s.id WHERE w.status = 'closed'",
  "assumptions": [
    {"dimension": "scope", "key": "closed-only", "assumption": "closed orders only; cancelled and reopened excluded", "basis": "status values + judgment", "confidence": 0.7},
    {"dimension": "behavior", "key": "throughput-is-a-flow", "assumption": "a flow: sums valid over any partition", "basis": "minutes per visit, one row per visit", "confidence": 1.0}
  ]
}$$;
```

The metric is now a view under its name, and you can query it at any
grain. A person's definition outranks the agent's, so if a person
corrects it, the person's version is what runs:

```sql
SELECT date_trunc('month', date) AS month, sum(value) AS hours
FROM throughput GROUP BY date_trunc('month', date)
ORDER BY month
```

More: [metrics](../usage/metrics.md).

## 10. Add a data test

Write the expectation down; never assume a breach rate of zero, since a
source with known dirt has its own. The test (`DECLARE TEST`) compares your
expectation with a function that measures the same property, and
`TESTS()` returns the result. The shipped `rate_tolerance` detector is
one-sided: green at or under the tolerance. To also catch
over-cleaning, declare a detector of your own that goes red on both
sides.

```glossql
DECLARE ASPECT duration_present WITH $${
  "type": "object", "required": ["outcome"],
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"},
                 "breach_rate": {"type": "number"}}
}$$ AS FACT ON TABLE WHEN entity = 'one site visit on a work order';
GLOSS duration_present ON work_orders AS $${
  "outcome": "Closed orders carry a positive on-site duration.", "tolerance": 0.01}$$;
DECLARE TEST duration_test ON duration_present BY (AGENT, HUMAN)
  DETECTOR rate_tolerance THRESHOLD 0.01;

DECLARE FUNCTION duration_present_check FOR ops AS $$
  SELECT 'measured: closed orders against positive durations' AS outcome,
         CASE WHEN count(*) = 0 THEN 0.0
              ELSE CAST(count(*) FILTER (WHERE duration_min IS NULL OR duration_min <= 0) AS DOUBLE) / count(*)
         END AS breach_rate
  FROM work_orders WHERE status = 'closed'
$$ RETURNS duration_present;

SELECT subject, band, score FROM TESTS(ops::duration_present);
```

More: [data tests](../usage/data-tests.md).

## 11. Read the metrics

`metric_series()` serves each metric's values at its finest grain, the
total and the slices along its dimensions, computed when you read it.
`metric_axes()` says what the catalog knows of each metric's columns:

```sql
SELECT name, title, unit, meaning, formula
FROM metric_surfaces ORDER BY name
```

```sql
SELECT metric, applicable, reason, behavior, floor, dims
FROM metric_axes() ORDER BY metric
```

```sql
SELECT metric, period, value FROM metric_series(grain := 'month')
WHERE dimension = '' ORDER BY metric, period
```

## 12. Answer the review questions

Every assumption below full confidence is a question for a person:

```sql
SELECT aspect, dimension, key, assumption, conf
FROM open_questions ORDER BY conf ASC;
```

Over MCP they arrive as forms on calls that read the catalog; in the
console they are the Review tab. An answer is stored as a review
decision, in the person's words, and the question closes. The agent
then records the metric definition again with the decision applied:

```sql
SELECT aspect, key, stance, folded_in FROM review_decisions ORDER BY written_at DESC
```

More: [the review queue](../usage/review.md).

## 13. Open the console

Open `http://127.0.0.1:8080/ops/app`. Review, Metrics, Quality,
Glossary and Lineage show what the catalog holds; Export and Query hand
the data over. More: [the console](../usage/console.md).

## 14. See what is left

Every tool result ends with two lines; the last one reads:

```text
next: work_orders_open → say how work_orders_open combines (next://ops/work_orders_open) · done: hours_logged, review
```

The test report: per served metric its worst test, with the statement
that settles it, then the review queue. The built-in tests are join
fan-out, orphaned keys on the declared joins and the additivity of the
value; the server runs them after a definition is written and after a
load. The work is done when every served metric's tests are green or
accepted and nothing waits on the agent. The link is an MCP resource;
the same rows come through the tool, with the statement to send:

```sql
SELECT surface, state, say, statement FROM next ORDER BY goal, surface
```

A statement there is a proposal: edit it, send it, or skip it.
`workspace_next` lists every surface the workspace can grow along, with
what exists, what is open for the agent, and what waits for a person:

```sql
SELECT surface, how, existing, open, waiting FROM workspace_next ORDER BY open DESC;
```

More: [next steps](../extending/next-steps.md).
