# Metric definitions — read before writing a metric's SQL

## Declare, describe, define

One metric is one name on the dataset. Declare it with a title only:

```glossql
DECLARE ASPECT throughput WITH $${"title": "Throughput"}$$ AS VIEW;
```

Its business description lives in the dataset's business glossary,
`definitions`: meaning, unit, owner, source, and for a derived metric
its `formula`. It is one annotation, so a write replaces the whole
map. Read it first, add your entry, write it back:

```sql
SELECT g.body FROM glossary g JOIN current_dataset d ON d.dataset = g.dataset
WHERE g.aspect = 'definitions' AND g.actor_kind = 'agent' ORDER BY g.written_at DESC LIMIT 1
```

```glossql
GLOSS definitions ON ops AS $${"definitions": {
  "throughput": {"meaning": "work completed and accepted; counted at completion date",
                 "unit": "hours", "owner": "Operations", "source": "KPI handbook v3 §2"},
  "backlog_days": {"meaning": "open work expressed in days of current throughput", "unit": "days",
                   "formula": "backlog[end of w] / throughput[w] * days[w]"}
}}$$;
```

A `formula` is documentation over other metrics' names, with the
window `w` free: `[w]` a sum over the window, `[end of w]` a level at
its end, `[w-1]` the previous window. Nothing computes it.

Then define the metric in one statement: the SQL, which column is the
time, which the measure and how it adds up, which columns slice it,
and every judgment call you made:

```glossql
GLOSS throughput ON ops AS $${
  "sql": "-- completed work: hours per closed order, at completion date\nSELECT w.completed_at AS date, w.duration_min / 60.0 AS value, w.region, s.service_line FROM work_orders w JOIN sites s ON w.site_id = s.id WHERE w.status = 'closed'",
  "time": "date",
  "measure": {"column": "value", "additivity": "additive", "unit": "hours"},
  "dimensions": ["region", "service_line"],
  "assumptions": [
    {"dimension": "scope", "key": "closed-only", "assumption": "closed orders only; cancelled and reopened excluded", "basis": "status values + judgment", "confidence": 0.7}
  ]
}$$;
```

Put the mechanics in SQL comments; they cannot drift from the query.

## The three shapes

**Additive (a flow).** Events that sum over time and over members.
Serve the rows as they are, no GROUP BY needed: the time column, the
value, the slicing columns. The example above.

**Semi-additive (a level, a stock).** A balance, a headcount, stock on
hand: it sums over members and never over time. Serve one row per
period, or one per entity and period. Served at event grain, every
row carries the right level and every sum is wrong. A running balance:

```glossql
GLOSS payables_outstanding ON fin AS $${
  "sql": "WITH daily AS (SELECT entry_date, sum(amount) AS delta FROM journal_lines GROUP BY entry_date) SELECT entry_date AS date, sum(delta) OVER (ORDER BY entry_date) AS value FROM daily",
  "time": "date",
  "measure": {"column": "value", "additivity": "semi-additive", "grounds": "the running balance at the day's end"}
}$$;
```

A table of intervals (from and to dates) is a level too: `+1` at the
start, `-1` at the end, summed running:

```glossql
GLOSS headcount ON hr AS $${
  "sql": "WITH events AS (SELECT from_date AS date, 1 AS delta FROM stints UNION ALL SELECT to_date AS date, -1 AS delta FROM stints WHERE to_date IS NOT NULL), daily AS (SELECT date, sum(delta) AS delta FROM events GROUP BY date) SELECT date, CAST(sum(delta) OVER (ORDER BY date) AS DOUBLE) AS value FROM daily",
  "time": "date",
  "measure": {"column": "value", "additivity": "semi-additive", "grounds": "open stints at the day's end"}
}$$;
```

**Ratio.** Serve the two halves beside `value` and name them. Totals
and coarser grains are then `sum(num) / sum(den)`, right for the
headline and for every member. A ratio marked additive is summed: a
dozen member ratios added into one wrong number.

```glossql
GLOSS backlog_days ON ops AS $${
  "sql": "WITH bl AS (SELECT date_trunc('month', date) AS m, region, sum(value) AS bal FROM backlog GROUP BY 1, 2), th AS (SELECT date_trunc('month', date) AS m, region, sum(value) AS th FROM throughput GROUP BY 1, 2) SELECT CAST(bl.m AS DATE) AS date, bl.bal / nullif(th.th, 0) * 30.0 AS value, bl.bal AS num, th.th / 30.0 AS den, bl.region FROM bl JOIN th ON th.m = bl.m AND th.region = bl.region",
  "time": "date",
  "measure": {"column": "value", "additivity": "ratio", "numerator": "num", "denominator": "den", "unit": "days"},
  "dimensions": ["region"]
}$$;
```

- A ratio can only be sliced by columns both halves carry. Pick the
  ones the question needs.
- A slice of a ratio is recomputed per member from its own halves,
  never averaged.
- **A distinct count or a median** adds up from nothing: distinct
  customers per region do not sum to distinct customers. Serve it with
  no dimension columns and say so in an assumption; a per-member count
  is its own metric.

## Assumptions: what a person must be able to see

- **Every judgment call is an assumption with a stable `key` and a
  confidence below 1**: what counts, which date, which status, which
  accounts. That is what the review asks a person. A defensible
  default is still a judgment; 1.0 silences the question.
- **What the data settles is yours, at 1.0**: a sign convention, a
  grain, additive or not. Measure it; never ask a person for it.
- **A basis that names a computation must be run.** "Ties to GL 4*
  net" is a second route to the number: run it against your result
  before you write it down. Keep it checked afterwards as
  `alternative_sql` on the assumption, or as a test
  (`references/validate.md`).
- **Name the strongest alternative, as SQL that runs.**

  ```json
  {"dimension": "definition", "key": "cycle-time-basis",
   "assumption": "cycle_time runs from dispatch to completion",
   "alternative": "from order creation to completion",
   "alternative_sql": "SELECT w.completed_at AS date, ... FROM ...",
   "basis": "operations convention", "confidence": 0.7}
  ```

  Often the best alternative is a second path the data already
  carries: a published total beside the lines, a control account
  beside its subledger. Look for one per metric; "no second path
  exists" is worth recording too.
- After defining several metrics, run `SELECT
  detect_grounding_collisions() FROM <dataset>`: two metrics with the
  same definition make every ratio between them 1.0.

## Defaults where the brief is silent

- Define on the row-level data; a pre-aggregated column beside it is
  the second path, never the basis.
- A ratio of sums takes each row whole: a null in either half drops
  the row from both.
- Metrics over the same rows use the same date column.
- Exclude what is impossible (violates an identity); keep what is
  merely unusual; disclose both.
- A null key does not remove a row from a count unless the brief
  names the entity counted. State the null share beside the number.
- A plan or a schedule is no evidence that its events happened.

## Serve or stop

**Serve with disclosure** when the dirt is bounded: you can say how
many rows it touches and which way it moves the number. Carry it as an
assumption below 1.0 with the count in the `basis`.

**Stop** when it is not: the rows are missing, a join key cannot be
trusted, the column was never loaded. Never serve a number from a
proxy. Record why in place of the SQL:

```glossql
GLOSS utilization ON ops AS $${
  "stopped": "capacity never loaded: the roster export carries no hours column, so hours worked / capacity cannot be served; closes when the export adds capacity_hours, or a person names contract hours as capacity",
  "assumptions": [
    {"dimension": "definition", "key": "capacity-source", "assumption": "capacity is the roster's planned hours, not contract hours", "basis": "operations convention", "confidence": 0.6}
  ]
}$$;
```

A stopped metric is a finding, not a failure. Say the same in your
summary. A person's definition with `sql` lifts the stop.
