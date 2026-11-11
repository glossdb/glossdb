# Kits

A kit packages the properties, measurements and tests for one use
case, as a SQL script of glossql statements. A kit adds vocabulary and
reads. It does not add grammar.

## The kits that ship

| Kit | From | Adds |
|---|---|---|
| `core` | glossdb | review decisions, load-query approvals and apps as annotations; the views `open_questions`, `review_decisions`, `view_definitions`, `workspace_status` |
| `kpi` | the extension | `meaning`, `entity`, `role`, `additivity`, `unit`, `dimension`, `conventions`, `definitions`; `column_profile()`, `outlier_profile()`; the `value_entropy` detector |
| `quality` | the extension | detection of relationships, hierarchies, derivations and duplicate definitions; `relationship_coherence()`, `additivity_evidence()`, `temporal()`; the `rate_tolerance` detector |
| `views` | glossdb | `view_summary()`, `metric_series()`, `view_tests()`, `view_sources()`, `fact_values()`, `semantic_model()`, `lineage_events()`; `time_grains`; the four built-in tests on a metric |
| `outlook` | glossdb | preview: expected ranges, forecasts, plans, scenarios |
| `goals` | glossdb | `open_items` and `next` |

The server loads them at each start, in this order. A kit the lake
already recorded with the same text runs nothing. The extension also
ships `spatial`, a small example the server does not load.

```sql
SELECT name, statements, loaded_at FROM kits;
```

## Write a kit

Statements in order: properties, then functions, then the tests that
name both.

```glossql
DECLARE ASPECT currency WITH $${
  "type": "object", "required": ["value"],
  "properties": {"value": {"type": "string", "pattern": "^[A-Z]{3}$"}}
}$$ AS FACT ON COLUMN WHEN unit = 'money';

DECLARE TEST currency_test ON currency BY (AGENT, HUMAN) DETECTOR value_entropy THRESHOLD 0.7;

DECLARE ASPECT unit_check WITH $${
  "type": "object", "x-subject": "view",
  "properties": {"applicable": {"type": "boolean"}, "breach_rate": {"type": ["number", "null"]},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION unit_check FOR GLOBAL AS $$
  WITH v AS (SELECT view, value_column FROM main.view_summary() WHERE view = split_part($subject, '.', 2)),
  u AS (SELECT count(*) AS n FROM main.glossary g, v
        WHERE g.subject = $subject || '.' || v.value_column AND g.aspect = 'unit')
  SELECT true AS applicable,
         CASE WHEN u.n > 0 THEN 0.0 ELSE 1.0 END AS breach_rate,
         CASE WHEN u.n = 0 THEN 'the value of ' || split_part($subject, '.', 2) || ' has no unit' END AS finding,
         CASE WHEN u.n = 0 THEN 'annotate unit on the value column' END AS fix
  FROM u
$$ RETURNS unit_check;

DECLARE TEST unit_stated_test ON unit_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;
```

- **A property** (`DECLARE ASPECT`) has a JSON Schema and a kind:
  `AS FACT` for a value someone states, `AS MEASUREMENT` for a
  function's result, `AS VIEW` for a view name. `ON` names the assets
  it applies to: `DATASET`, `TABLE`, `COLUMN`, `RELATIONSHIP`,
  `SOURCE`.
- **A condition** makes a property required only where it applies:
  `WHEN role = 'measure'` by another property's value, `WHEN TYPE =
  'GEOMETRY'` by the column's type.
- **A measurement** is a function with `RETURNS`. Its body is one SQL
  query. `$subject` is the asset it runs over, and
  `subject_column($subject)` is that column as a relation with one
  column `v`. The result is validated against the property's schema
  and stored. It is served again while the tables and catalog tables
  it read are unchanged.
- **A detector** is a function without `RETURNS`. It reads the test's
  `annotations` and returns `subject`, `state`, `score`. `$threshold`
  is the test's.
- **A test on each metric.** `"x-subject": "view"` on the property
  marks a test the server expects on each metric and runs itself:
  after the metric is defined, after its columns are annotated, and
  after a load of a table it scans. Its function runs over
  `<dataset>.<metric>`.
- **Rows in `next`.** A test that is not green is a row of `next`.
  A check that returns `finding` and `fix` has them served as the
  row's `open` and `statement`. A kit adds no other code for this.

## Load a kit

```glossql
FROM glossql_kit('/opt/kits/billing/kit.sql');
```

`glossql_kit` runs the script one statement at a time and returns one
row per statement with its outcome. A failing statement stops the
load; the ones before it stay. The load is recorded in `kits`, and its
tests show as `kit:<name>` in `view_tests()`. An agent without access
to the server's files sends the same statements through the tool.

Loading again does nothing for unchanged declarations. A changed
property that already has annotations is refused.

## Test a kit

The server's kits each have a suite beside them, `kits/<kit>/kit.test`,
in DuckDB's sqllogictest form. `cargo test -p glossdb-duck` runs them.

## Teach the kit

An agent needs to know what the kit's words mean and in what order to
work. That text is a skill under `skills/`, served to agents over
MCP: the skill's `SKILL.md`, or a page under its `references/`. Its
fenced examples are parsed and bound by the suite.
