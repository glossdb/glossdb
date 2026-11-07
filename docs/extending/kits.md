# Kits

A kit is a SQL script of glossql declarations: properties (aspects),
functions, tests, and table macros that read them. It adds vocabulary
and reads to the language, never grammar. A kit ships with a
`SKILL.md` that teaches an agent what its words mean, and a test suite.

## The kits that ship

From the glossql extension:

| Kit | Adds |
|---|---|
| `kpi` | the semantic layer's vocabulary: `meaning`, `role`, `behavior`, `unit`, `dimension`, `entity`, `conventions`, `definitions`; the column profiles; the `slot_entropy` detector ([the KPI kit](../reference/kpi-kit.md)) |
| `quality` | how the data holds together: relationship, hierarchy and derivation discovery, relationship coherence, duplicate metrics, stock-or-flow evidence, the `temporal` profile, the `rate_tolerance` detector |
| `spatial` | a small domain example: a shape and a coordinate system on every geometry column, and a geometry profile. Not loaded by the server |

From glossdb:

| Kit | Adds |
|---|---|
| `core` | the server's own properties (review decisions, load-query approval, apps as annotations) and the catalog's views: `open_questions`, `review_decisions`, `current_dataset`, … |
| `metrics` | the metric series: `metric_series()`, `metric_axes()`, `metric_sources()`; the `ladder` on a period column |
| `outlook` | preview: forecasts, expected ranges, plans and scenarios through the model service |
| `goals` | `open_items`, what waits on an action, and the next steps of the core goals |

The server loads them at every open, in order: `core`, `kpi`,
`quality`, `metrics`, `outlook`, `goals`. A kit whose text the lake
already recorded is current and runs nothing, so an unchanged workspace
opens fast. The views and functions each kit declares:
[views and table functions](../reference/reads.md),
[functions](../reference/functions.md).

## Tests

Every kit has a suite in DuckDB's sqllogictest form. The server's sit
beside each kit as `kits/<kit>/kit.test` and run with `cargo test -p
glossdb-duck`; the extension's are `test/sql/glossql_kit_<kit>.test`
in its repository.

## Writing a kit

A kit is statements in order: properties first, then the functions,
then the tests that name both.

```glossql
DECLARE ASPECT currency WITH $${"type": "object", "required": ["value"],
  "properties": {"value": {"type": "string", "pattern": "^[A-Z]{3}$"}}}$$
  AS FACT ON COLUMN WHEN role = 'measure';
DECLARE ASPECT min_max WITH $${"type": "object", "required": ["min", "max"]}$$ AS MEASUREMENT ON COLUMN;
DECLARE FUNCTION min_max FOR GLOBAL AS
  $$ SELECT min(v) AS min, max(v) AS max FROM subject_column($subject) $$ RETURNS min_max;
DECLARE TEST currency_w ON currency BY (AGENT, HUMAN) DETECTOR slot_entropy THRESHOLD 0.7;
```

- **Schemas.** A property's `WITH` is a JSON Schema. Every `FACT`
  value and every measurement's output is validated against it.
  Annotations such as `title` or `x-kind` sit beside the structure.
- **Conditions.** `WHEN role = 'measure'` makes the property required
  only where the column's role says so.
- **Measurements.** A function with `RETURNS` becomes a table macro in
  the dataset's schema (`glossql` for `GLOBAL`). `$subject` is its
  parameter; `subject_column($subject)` is the column as a relation
  named `v`. A measurement is tied to the tables and catalog relations
  its plan reads, and served again while they are unchanged. A body
  that reads a file or another database is tied to everything, so a
  kit's measurements should read tables.
- **Detectors.** A function without `RETURNS` runs when its test is
  read, over the values written for the aspect, with `$threshold`
  bound, and returns `(subject, band, score)`. A detector that fails
  returns band `error`, never a failed read.
- **Metric definitions.** Every `VIEW` annotation is checked against
  the definition contract (`sql` or `stopped`, `assumptions`). A kit
  whose readers need a body key of their own declares a schema for it
  as an aspect with `"x-kind": "grounding"`.
- **Next steps.** A kit can add goals to `next`:
  [next steps](next-steps.md).

Write the `SKILL.md` too: what each word means, in what order an agent
works, what a reader expects. The engine checks the statements; the
skill is the half it cannot check.

## Loading a kit

A kit is statements, so a kit of your own is sent like any statements:
through the MCP interface, or with `FROM glossql_kit('<path>')` where
the server can read the file. `glossql_kit` runs the script one
statement at a time and returns one row per statement; a failing
statement stops the load, and the ones before it stay. The load is
recorded in `kits` with its path and statement count. Loading again is
a no-op for unchanged properties; a changed property that already has
annotations is refused.

A kit that installs a DuckDB extension, as `spatial` does, needs an
actor named in `GLOSSDB_ROOT` ([configuration](../operations/configuration.md)).
