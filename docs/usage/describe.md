# Describe

Describing a dataset fills the glossary: the business glossary and the
data catalog in one store, kept in the lake. An annotation (`GLOSS`)
is a value for one property on one asset: a dataset, a table, a
column, a relationship or a source.

## Annotate

```glossql
USE hr;
GLOSS entity ON staff AS $${"value": "one row per employee and contract",
  "role": "dimension", "grain": ["employee_id", "contract_no"]}$$;
GLOSS meaning ON staff.fte AS $${"value": "contracted share of a full week, 0 to 1"}$$;
GLOSS role ON staff.fte AS $${"value": "measure"}$$;
GLOSS additivity ON staff.fte AS $${"value": "semi-additive", "basis": "a level per person, not an event"}$$;
GLOSS unit ON staff.fte AS $${"value": "FTE"}$$;
GLOSS role ON staff.department AS $${"value": "dimension"}$$;
```

Each body is JSON, validated on write against the property's JSON
Schema. The engine records who wrote it: an agent on the MCP paths, a
person on the others. No statement names its own author.

## The properties that ship

A property (`ASPECT`) is declared with a JSON Schema and the kind of
asset it applies to. The `kpi` kit declares these:

| Property | On | Value |
|---|---|---|
| `meaning` | table, column, relationship | `value`: what it is, in words; `term` |
| `entity` | table | `value`: what one row is; `role` (`fact`, `dimension`), `grain` (the key columns), `time_axis` |
| `role` | column | `key`, `measure`, `dimension`, `timestamp` or `attribute` |
| `additivity` | a measure column | `additive`, `semi-additive`, `ratio` (with `numerator`, `denominator`) or `non-additive`; `basis` |
| `unit` | a measure column | `value`; `source_column` |
| `dimension` | a dimension column | `primary`, `supporting` or `none` |
| `conventions` | source | free JSON: what each export of that system carries |

`additivity`, `unit` and `dimension` are required only where the
column's `role` says so. The views kit adds `time_grains` on a
timestamp column and `validity` on an effective-dated table
([define views](views.md), [test](test.md)). Each declared property:

```sql
SELECT name, kind, grains, condition FROM aspects ORDER BY name;
```

## Relationships

A relationship is declared, not annotated. `->` is many-to-one, `<->`
one-to-one. A composite key is a tuple.

```glossql
DECLARE RELATIONSHIP staff.department -> departments.code;
DECLARE RELATIONSHIP absences.(employee_id, contract_no) -> staff.(employee_id, contract_no);
```

## Measure before you state

A measurement is a function run over an asset. Its result is stored
with the lake snapshot it read at and served again until something it
read changes after that snapshot.

```glossql
SELECT column_profile() FROM staff.department;
SELECT detect_relationships() FROM hr;
SELECT relationship_coherence() FROM staff.department -> departments.code;
```

| Function | Over | Returns |
|---|---|---|
| `column_profile()` | a column | `total`, `null_ratio`, `distinct`, `min`, `max` |
| `outlier_profile()` | a column | outliers by interquartile range and modified z-score |
| `temporal()` | a timestamp column | grain, completeness and gaps |
| `additivity_evidence()` | a measure column | evidence for additive or semi-additive |
| `detect_hierarchies()` | a table | columns that determine other columns |
| `detect_derivations()` | a table | numeric columns computed from two others |
| `detect_relationships()` | a dataset | candidate keys between tables |
| `relationship_coherence()` | a declared relationship | `filled`, `orphans`, `orphan_rate`, and the dates of the two tables compared |
| `detect_definition_collisions()` | a dataset | views that compute the same thing |

A detection proposes; a declaration is yours to make.

## Read the glossary

```glossql
SELECT subject, aspect, value, test_state, state FROM GLOSSARY(staff);
```

`GLOSSARY(<asset>)` returns one row per asset and property for the
asset and what lies under it; with no argument, the dataset in use.
The value is the person's where one exists, else the agent's, else a
measurement's.

### States

| `state` | Meaning |
|---|---|
| `current` | served; the asset is unchanged since the write |
| `stale` | served and marked: a load redefined, retyped or dropped the column, or an input of the measurement changed |
| `possibly` | a computed value served and marked: a result it read is out of date and not computed again yet |
| `missing` | required and not annotated; the row still appears |
| `conflict` | a person's and an agent's values differ beyond the test's threshold; the value is withheld |

Each value side by side, with its author:

```glossql
SELECT subject, aspect, actor, body, written_at, current FROM GLOSSARY(staff.fte, all => true);
```

## What is still missing

`next` lists the required annotations nobody wrote, with the
statement that writes each. On the assets your views read or serve
they are `should`; on the tables and columns no view reads they are
`could`, written when a person asks. Two values that conflict are a
`must`:

```sql
SELECT level, asset, state, open, statement FROM next WHERE kind = 'describe';
```

Annotations are append-only. A new value from the same kind of actor
replaces that actor's earlier value at read; the history stays in the
`glossary` table. Removal is SQL: `DELETE FROM glossary WHERE …`.
