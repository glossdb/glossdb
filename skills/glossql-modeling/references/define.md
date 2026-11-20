# Defining views: tables, single values, metrics, and a table to a data contract

Read before writing a view's SQL.

## Declare, then define

A view is one name on the dataset. Declare it with a title and its
kind, then define it. The definition is one annotation on the
dataset; writing it again replaces it.

| Kind | Declared with | Serves | Read with |
|---|---|---|---|
| a table | `"x-kind": "relation"` | rows | `FROM <view>` |
| a single value | `"x-kind": "scalar"` | one row with a column `value` | `fact_values()`, `FROM <view>` |
| a metric | no `x-kind` | a value per period, with dimensions | `metric_series()`, `FROM <view>` |

The definition's body holds:

- `sql`, the query; or `stopped`, the reason no query is given.
- `assumptions`: the judgment calls, each `{"dimension", "key",
  "assumption", "basis", "confidence"}` and optionally
  `"alternative"`. The review asks a person about each one with a
  `key` and a confidence below 1
  (`skill://glossql/references/review.md`).
- for a metric: `time`, `measure` and `dimensions` (below).

The statement answers with the view's row of `view_summary()`. A view
can read another view by name, so a decision on one reaches every
view built on it. Put the mechanics in SQL comments inside `sql`.
Spell the `GROUP BY` out.

A view's meaning is its `meaning` annotation (`GLOSS meaning ON
<dataset>.<view>`), which `next` asks for. A metric's unit is the
`unit` of its `measure`. `view_definitions` shows both.

## A table to a data contract

The job: source files in, one cleaned table out, in a format someone
else fixed. The contract names the table, its key, the columns with
types and meanings, and the code tables.

1. **Load the sources as they are.** Typing only: casts, trims, null
   markers (`load.md`). No row is left out in a load query.
2. **Build the table as a table view.** Select the contract's
   columns, in its order, cast to its types.
3. **State every rule you applied as an assumption**: a recoded
   value, a duplicate resolved, rows left out. State also what you
   kept as it is where the contract does not give the form of a text
   or id column: letter case, padding, the format of an id. Without
   that line nobody learns that a choice was made.
4. **Describe the table**: `entity` and `meaning` on the view,
   `meaning` and `role` on each column; `next` lists them.
5. **State the contract on the view**: the key as the `grain` of its
   `entity`, a `contract` on each column (type, required, allowed
   values). The server tests the rows against it after each write
   (`contract_test`). The forms, the tests and how to close them:
   `harmonise.md`, step 5, which holds for one source as for several.

```glossql
DECLARE PROPERTY staff WITH $${"title": "Staff", "x-kind": "relation"}$$ AS VIEW;
GLOSS staff ON hr AS $${
  "sql": "SELECT employee_id, trim(full_name) AS full_name, CAST(hired_on AS DATE) AS hired_on, upper(trim(department)) AS department_code FROM hr_export WHERE employee_id IS NOT NULL QUALIFY row_number() OVER (PARTITION BY employee_id ORDER BY exported_at DESC) = 1",
  "assumptions": [
    {"dimension": "scope", "key": "latest-export-row", "assumption": "where an employee_id repeats, the row of the newest export is kept", "basis": "14 ids repeat, each with one newer row", "confidence": 0.7},
    {"dimension": "scope", "key": "no-id-left-out", "assumption": "rows without an employee_id are left out", "basis": "3 rows, all without a name", "confidence": 0.8},
    {"dimension": "convention", "key": "department-upper-case", "assumption": "department codes are served in upper case", "basis": "the code table is upper case; 9 rows are lower case", "confidence": 0.9},
    {"dimension": "convention", "key": "employee-id-as-exported", "assumption": "employee_id is kept as exported, with leading zeros and no prefix; the contract gives no format", "basis": "ids are 5 or 6 digits in the export", "confidence": 0.6}
  ]
}$$;
```

```glossql
GLOSS entity ON hr.staff AS $${"value": "one employee", "role": "dimension", "grain": ["employee_id"]}$$;
GLOSS contract ON hr.staff.employee_id AS $${"type": "VARCHAR", "required": true}$$;
GLOSS contract ON hr.staff.hired_on AS $${"type": "DATE", "required": true}$$;
GLOSS contract ON hr.staff.department_code AS $${"type": "VARCHAR", "required": true, "values": ["ENG", "OPS", "FIN"]}$$;
```

A rule the contract has no word for (a hire date not in the future) is
a test of your own (`tests.md`). Where the export states its own key,
state it on the loaded table as well: `grain_test` holds each load
against it, before any view reads the rows.

## A metric

A metric is SQL with a period column, a value column and the columns
that slice it. Say which is which in the definition:

- `time`: the period column.
- `measure`: `{"column", "additivity", "unit"}`; a ratio adds
  `"numerator"` and `"denominator"`, the columns that hold its halves.
- `dimensions`: the slicing columns; the first is the primary one.

The server writes these as annotations on the view's columns (`role`,
`additivity`, `unit`, `dimension`) and profiles the period column. You
can write the same annotations yourself, on `<view>.<column>`.

- **Additive**: events that sum over time and over members (parcels,
  hours). Serve the rows as they are; no `GROUP BY` is needed.
- **Semi-additive**: a level, such as headcount or stock on hand. It
  sums over members and not over time. Serve one row per period, or
  one per member and period. From a table of intervals, add 1 at each
  start and subtract 1 at each end, and take the running sum.
- **Ratio**: serve the two halves beside the value and name them.
  Totals and coarser grains are the summed numerator over the summed
  denominator. A ratio can be sliced only by columns both halves
  carry.
- **Non-additive**: a distinct count or a median does not add up from
  parts. Serve it without dimension columns and say so in an
  assumption. A count per member is a metric of its own.

```glossql
DECLARE PROPERTY on_time_rate WITH $${"title": "On-time delivery rate"}$$ AS VIEW;
GLOSS on_time_rate ON logistics AS $${
  "sql": "SELECT delivered_on, depot_id, count(*) FILTER (WHERE delivered_on <= promised_on) AS on_time, count(*) AS total, count(*) FILTER (WHERE delivered_on <= promised_on) / count(*)::DOUBLE AS value FROM deliveries GROUP BY delivered_on, depot_id",
  "time": "delivered_on",
  "measure": {"column": "value", "additivity": "ratio", "numerator": "on_time", "denominator": "total", "unit": "share"},
  "dimensions": ["depot_id"]
}$$;
```

Where rows have to be combined and the value column has no
`additivity`, `metric_series()` refuses and names the annotation to
write. Reading a metric: `time-grains.md`.

## Serve or stop

Serve with an assumption when the defect is bounded: you can say how
many rows it touches and which way it moves the number. Put the count
in the `basis`. Stop when it is not: rows are missing, a join key
cannot be trusted, a column was not loaded. Do not serve a number
from a stand-in. Record the reason in place of the SQL:

```glossql
GLOSS utilisation ON fleet AS $${
  "stopped": "the workshop export has no capacity column, so hours booked over hours available cannot be computed; it can be defined when the export carries capacity_hours"
}$$;
```

A stopped view is a finding to report. A definition with `sql`, yours
or a person's, lifts the stop.

## Defaults where the request is silent

- Define on row-level data. A pre-aggregated column beside it is a
  second route to check against, not the basis.
- Views over the same rows use the same date column.
- Leave out what is impossible, keep what is unusual, and state both.
- Two views with the same SQL are probably one: `SELECT
  detect_definition_collisions() FROM <dataset>` finds them.
