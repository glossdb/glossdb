# Describing tables and columns

You describe data in two steps. You declare a property the harness asks
for (an aspect): a name, a JSON Schema for its values, and a kind. Then
an agent or a person annotates an asset with a value for it (`GLOSS`).
A property must be declared before anyone can annotate it. The language
reference is [SPEC.md §5](https://github.com/glossdb/glossql/blob/main/SPEC.md).

The `kpi` kit declares the properties most datasets need: `meaning`,
`role`, `additivity`, `unit`, `dimension`, `entity`, `conventions`,
`definitions` ([the KPI kit](../reference/kpi-kit.md)).

## Declare a property

```glossql
DECLARE ASPECT unit WITH $${
  "type": "object",
  "properties": {"value": {"type": "string"}, "source_column": {"type": "string"}}
}$$ AS FACT;

DECLARE ASPECT min_max WITH $${
  "type": "object",
  "properties": {"min": {}, "max": {}}
}$$ AS MEASUREMENT ON COLUMN;
```

The kind says who provides the value:

| Kind | Value | Example |
|---|---|---|
| `FACT` | stated by an agent or a person, validated against the `WITH` schema | a unit, a convention, a constant, a formula |
| `MEASUREMENT` | computed by a function from the data; never annotated by hand | `min_max`, outliers, relationship candidates |
| `VIEW` | SQL, served as a view under the property's name | a metric, a single value, a derived relation ([metrics](metrics.md)) |

A measurement's value is the newest result of the function that
returns it ([measurements](measurements.md)).

## Choose what it applies to

A property applies to assets: a dataset, a table, a column, a declared
relationship (`orders.customer_id -> customers.id`, a composite key as
a tuple), or a source.

- `ON DATASET | TABLE | COLUMN | RELATIONSHIP | SOURCE` lists the kinds
  of asset the property applies to. Without the clause it applies to
  any asset, as spelled. A `VIEW` property always applies to the
  dataset.
- `ON TABLE` and `ON COLUMN` also require the asset to be loaded: an
  annotation on a table or column that is not in the dataset is
  refused, and the refusal names what is.
- A condition makes the property required only where another property
  has a value: `ON COLUMN WHEN role = 'measure'` requires it on a
  column while that column's `role` is `measure`. The condition decides
  what is required and counted as missing; it never blocks a write.
- `ON SOURCE` makes the asset a source's name. Sources belong to the
  workspace, so the value is read in every dataset
  ([source conventions](loading-data.md#record-source-conventions)).

A required property nobody has annotated shows as `missing` in
`GLOSSARY()`, on the assets it applies to only.

## Annotate

```glossql
GLOSS revenue ON fin.journal_lines AS $${
  "sql": "SELECT debit_amount - credit_amount FROM journal_lines WHERE account_type = 'revenue'",
  "assumptions": [
    {"dimension": "sign", "assumption": "ledger stores debits positive",
     "basis": "column_stats", "confidence": 0.9}
  ]
}$$;
```

An annotation is validated on write and stored with its author and the
data snapshot. Annotating again replaces the value at read; the old row
stays as history ([how the catalog keeps history](workspaces.md#how-the-catalog-keeps-history)).
A person's annotation outranks an agent's.

Good practice:

- **Several values go in one body.** Use an array in the schema, not
  several statements.
- **Say when a property does not apply.** Where a property can fail to
  apply, annotate `none` with the grounds: a missing value and a value
  judged absent are different facts.
- **Keep what changes in annotations.** A declaration cannot change
  once annotations exist under it, but an annotation can be replaced,
  with its author and time. So a property's `WITH` blob holds the
  schema, a display title and tooling flags; what the company revises,
  such as a metric's meaning, unit and owner, goes in the
  `definitions` annotation ([metrics](metrics.md)).

## Change a property

Declaring a property again with the same content does nothing.
Changing it while annotations exist under it is refused, so stored
values never stop matching their schema.
