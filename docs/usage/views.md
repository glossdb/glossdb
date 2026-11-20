# Define views

Everything an agent or a person keeps on a dataset is a view: named
SQL on the dataset, read as `FROM <dataset>.<name>`, with its reason.
Its kind, in the definition, says what it is for:

| Kind | `"kind"` | What it is |
|---|---|---|
| a plain view | none | a query worth keeping, with its reason. It asks for nothing more |
| a table | `"table"` | rows: cleaned, joined or filtered data that people and other views read |
| a single value | `"value"` | one row with a `value` column |
| a metric | `"metric"` | a value per period, sliced by dimensions |
| a rule | `"rule"` | the rows that break a rule. It returns none while the rule holds; a test runs on it after every write |

A plain view keeps the evidence behind a decision: a profile, a
comparison of two sources, the values a mapping covers, a unit. A
table, a single value and a metric are what the dataset serves: the
server asks for their descriptions and runs the built-in tests on
them ([test](test.md)). A function is a kit's machinery, one stored
value per asset; a query worth reading again is a view.

## Define

One statement defines a view: an annotation on the dataset with its
SQL. The first definition of a name declares it; a new one replaces
it.

```glossql
USE stays;
GLOSS confirmed_bookings ON stays AS $${
  "kind": "table", "sql": "SELECT b.booking_id, b.check_in, b.nights, b.room_id, r.room_type FROM bookings b JOIN rooms r ON r.room_id = b.room_id WHERE b.status = 'confirmed'",
  "assumptions": [
    {"dimension": "scope", "key": "confirmed-only",
     "assumption": "tentative and cancelled bookings are left out",
     "basis": "status values", "confidence": 0.7}
  ]
}$$;

GLOSS room_count ON stays AS $${"kind": "value", "sql": "SELECT count(*) AS value FROM rooms"}$$;

GLOSS status_values ON stays AS $${"sql": "SELECT status, count(*) AS bookings FROM bookings GROUP BY status",
  "meaning": "the booking statuses the export carries; confirmed_bookings keeps one of them", "tags": ["status"]}$$;

GLOSS stay_has_room ON stays AS $${"kind": "rule",
  "sql": "SELECT b.booking_id FROM bookings b LEFT JOIN rooms r ON r.room_id = b.room_id WHERE r.room_id IS NULL",
  "meaning": "every booking names a room of the hotel"}$$;
```

The body holds `sql`, or `stopped` with the reason no query is
served; `kind`; `meaning` and `tags`, written as the view's
annotations of those names; and `assumptions`. The server answers the
definition of a table, a single value or a metric with the view's row
of `view_summary()`: whether it is served, and what it still needs. A
person's definition of a view outranks an agent's
([review and decide](review.md)).

A view and a loaded table of one dataset do not share a name. A view
may read other views.

## A metric

A metric's definition also says which column is the time, which the
measure and how it adds up, and which columns slice it:

```glossql
GLOSS booked_nights ON stays AS $${
  "kind": "metric", "sql": "SELECT check_in, nights AS value, room_type FROM confirmed_bookings",
  "time": "check_in",
  "measure": {"column": "value", "additivity": "additive", "unit": "nights"},
  "dimensions": ["room_type"]
}$$;
```

The server writes these as annotations on the view's columns (`role`,
`additivity`, `unit`, `dimension`; the first dimension is `primary`)
and profiles the time column with `temporal()`. You can write the same
annotations yourself on `<dataset>.<view>.<column>`.

### Additivity

| `additivity` | Combines over periods and members | Serve |
|---|---|---|
| `additive` | sums | the rows as they are |
| `semi-additive` | keeps the period's last level, summed over members | one row per period, or per entity and period |
| `ratio` | the summed numerator over the summed denominator | the two halves beside `value`, named in `measure` |
| `non-additive` | does not combine | one row per period |

```glossql
GLOSS occupancy ON stays AS $${
  "kind": "metric", "sql": "SELECT night AS period, sold / nullif(available, 0) AS value, sold, available, room_type FROM room_nights",
  "time": "period",
  "measure": {"column": "value", "additivity": "ratio", "numerator": "sold", "denominator": "available", "unit": "share"},
  "dimensions": ["room_type"]
}$$;
```

Where rows must be combined and the value column has no current
`additivity`, `metric_series()` refuses and names the annotation to
write. It sets no default.

### Time grains

The series is served at the metric's finest grain, its floor: the
grain `temporal()` measured on the time column. Where the dates
follow no regular grain, or you want another, state it:

```glossql
GLOSS time_grains ON booked_nights.check_in AS $${"floor": "week"}$$;
```

Each grain serves a window of whole periods counted back from the
newest data: 1440 minutes, 720 hours, 548 days, 156 weeks, 48 months,
40 quarters or 20 years. `"windows": {"month": 120}` changes one.
`metric_series()` serves that window and not the periods before it;
`window_periods` in `view_summary()` is the count for each metric.

## Assumptions

Each judgment call in a definition is an assumption with a stable
`key` and a `confidence` below 1: what counts, which date, which
status. A keyed assumption below full confidence goes to the review
queue ([review and decide](review.md)). What the data settles, such
as a sign or a grain, is measured, not asked.

## A target table with a contract (preview)

A table view that maps several systems of record onto one format
carries a data contract, with the harmonise kit loaded. The key is
the view's `entity` grain. Each column carries a `contract`: its type,
whether a value is required, the allowed values. A code table is a
relationship from the view's column.

```glossql
GLOSS entity ON supply.onhand AS $${"value": "the stock of one part at one site", "role": "fact", "grain": ["part", "site"]}$$;
GLOSS contract ON supply.onhand.site AS $${"type": "VARCHAR", "required": true, "values": ["CH10", "DK01", "DK02", "PL01"]}$$;
GLOSS contract ON supply.onhand.cases AS $${"type": "DOUBLE", "required": true}$$;
```

After each write the server runs `contract_test` on the view: the
rows keep the contract. A red test is a `must` row of `next` with the
breaches per column, their rows and example values. A column of the
view with no contract is a `should` row. Name every code in the CASE
and leave the rest to NULL: a new code then shows as an empty required
value in `contract_test` instead of falling to the `ELSE`
([reads](../reference/reads.md#the-harmonise-kit-preview)).

## Stop instead of serving

Where the data cannot carry the view, state why in place of the SQL.
The view serves nothing, readers get the reason, and a person's
definition with `sql` lifts the stop.

```glossql
GLOSS revenue_per_room ON stays AS $${
  "stopped": "room rates were not loaded: the export carries nights and no price"
}$$;
```

## The business glossary of the views

A view's meaning is its `meaning` annotation, written in the body or
as `GLOSS meaning ON <dataset>.<view>`, and a metric's unit is its
measure's. `view_definitions` serves both.

```glossql
GLOSS meaning ON stays.occupancy AS $${"value": "sold room nights over available room nights"}$$;
```

A view's `tags` are found by `find()` with its name, its meaning and
the columns it reads ([tags](describe.md#tags),
[find](read.md#find-what-a-dataset-keeps)).

## Read what you defined

```sql
SELECT name, kind, unit, defined, stopped FROM main.view_definitions;
```

```sql
SELECT view, kind, applicable, reason, floor, additivity, dims, missing, measurements_to_run
FROM view_summary();
```

`view_summary()` has a row for each table, single value and metric.
`applicable` says whether a metric's series is served, and `reason`
what to change when it is not. A table and a single value have no
series: `applicable`, `reason` and `floor` are empty on their rows.
`missing` lists the annotations the columns still need,
`measurements_to_run` the measurements to run. Reading the views:
[read the views](read.md). Each column: [reads](../reference/reads.md).
