# Terms

The words glossdb and glossql use, beside the industry's. Each is
defined once here. How they fit together: [how it works](how-it-works.md).

## The language

| Term | Industry word | What it is |
|---|---|---|
| asset (subject) | asset | What a value attaches to: a dataset, a table, a column, a relationship, a source, a view and its columns |
| aspect | property of the harness schema | One property the harness asks for, with a JSON Schema, the assets it applies to, and when it is required |
| an aspect's grain | scope | What the aspect applies to: `ON COLUMN`, `ON TABLE`, the dataset |
| `FACT` aspect | asserted property | A value an actor states |
| `MEASUREMENT` aspect | computed property | A value a function computes from the data |
| `VIEW` aspect | view | SQL served as a view under the aspect's name: a metric, a scalar, or a derived relation |
| gloss | annotation | One actor's value for one aspect on one asset, validated and versioned |
| function | measurement | One SQL query that measures the data; its result is stored with its provenance |
| detector | scoring function | A function that scores how far the values for an aspect agree |
| test (`DECLARE TEST`) | data test | Declared on an aspect: who may annotate it and which detector scores agreement, with a threshold |
| `TESTS()` | test results | One row per asset and aspect: band, score, whether it is current |
| `GLOSSARY()` | the glossary | What is known: one row per asset and aspect, with its state |
| `current` · `stale` · `conflict` · `missing` | valid · outdated · conflict · missing | The state of an asset's aspect in the glossary |
| band | severity, confidence | green, yellow, orange, red, or error |
| `pin`, `reads` | provenance | The versions of what a measurement read |
| source | connection | A directory, a URL prefix, or an attached database |
| `RECIPE` | load query | The SQL that loads a table from a source |
| `IMPORT` | load | Runs a load query; every load is a DuckLake snapshot with its row count and column lineage |
| `PREVIEW` | dry run, preview | Runs a query on a source without loading |
| kit | rule pack | A domain's aspects, functions and tests, with a skill that teaches them |
| actor | user, service account | An agent, a person, or a person working with an agent |

## The semantic layer (the `kpi` kit)

| Term | Industry word | What it is |
|---|---|---|
| `meaning` | description | What a table, column or relationship means, and the business term it carries |
| `role` | column role | key, measure, dimension, timestamp, attribute |
| `unit` | unit of measure | A measure's unit or currency |
| `additivity`: additive · semi-additive · ratio · non-additive | additivity | Whether a measure may be summed, and over which axes |
| `dimension`: primary · supporting | dimension | Whether a dimension column is one to slice a metric by |
| `entity` | grain and key | What one row of a table is, and the columns that identify it |
| `definitions` | business glossary | Each metric's meaning, unit, owner, source and formula, kept per dataset |
| `conventions` | source conventions | A source's fiscal calendar, sign conventions, what its nulls mean |
| time grains | time grains | day, week, month, quarter: the grains a metric is served at |
| metric definition | metric | A view whose columns carry role, additivity and time |

## The semantic model in Ossie's words

Apache Ossie (incubating), formerly Open Semantic Interchange, is the
open format for exchanging a semantic model between BI tools, catalogs
and agents. A document holds one model: `datasets`, each with `fields`
and `metrics`; `relationships`; `ai_context` at every level. Beside
ours:

| Ossie | glossql | Note |
|---|---|---|
| the model (`name`, `description`) | dataset | one document per dataset |
| `datasets[]`: `name`, `source`, `primary_key`, `unique_keys` | table, with its `entity` | the keys from the entity's identity |
| `fields[]` with `dimension.is_time` | column with `role` timestamp | |
| `fields[]` with `dimension` | column with `role` dimension or attribute, ranked by `dimension` | |
| `metrics[].expression.sql` | metric definition (a `VIEW` aspect) and `additivity` on its value | Ossie's metric is an aggregate expression; ours is a row-grain view whose value's additivity says how it aggregates |
| `relationships[]`: `from_columns`, `to_columns` | `DECLARE RELATIONSHIP` | |
| `ai_context`: `instructions`, `synonyms`, `examples` | `meaning`, `definitions`, `conventions` | |
| `custom_extensions` | `unit`, tests, review decisions | what Ossie does not carry rides here on export |

An export to Ossie and an import from it are planned.

## Tests

| Term | Industry word | What it is |
|---|---|---|
| `fan_out_test` | join fan-out, many-to-many join | Two tables a metric scans share a key that repeats on both sides; the join multiplies rows unless the definition reduces one side to one row per key before the join |
| `orphan_test` | referential integrity, orphaned keys; dbt's `relationships` test | The share of rows on a declared join between tables the metric scans whose key finds no parent |
| `measure_additivity_test` | additivity: additive, semi-additive, non-additive measures | Whether the metric's value column says how it combines over time and members |
| `metric_tests()` | test results per metric | Every test on each metric and on what it reads, worst first, with the statement that runs it |
| `red` · `not_run` · `green`, `current` | fail · skipped · pass, fresh | A test's state in `metric_tests()`, and whether its result still holds |
| `tolerance`, `breach_rate` | threshold, failure rate | The rate a person accepts; the violation share a check measures |

## The server

| Term | Industry word | What it is |
|---|---|---|
| workspace | catalog, lakehouse | One DuckLake holding the datasets, their data and the catalog |
| dataset | schema | A schema of the lake: tables loaded from sources, and their views |
| the catalog | metadata catalog | The `glossql_*` tables beside the lake's own: declarations, annotations, measurements, loads |
| MCP interface | MCP server | `/mcp` and `/<dataset>/mcp`: one tool for glossql and SQL |
| query endpoint | Arrow over HTTP | `/<dataset>/query`: a query in the request body, an Arrow IPC stream back |
| console | data catalog UI | `/<dataset>/app`: the review queue, metrics, quality, a page per table and column |
| goal | objective | One row of `next`: a served metric with its tests, the review queue, and the preview goals bands and plan where a model service is named |
| `next` | next steps, test results | The line every MCP result ends with: per served metric its worst test and the statement that settles it, then the review queue |
| review queue (`open_questions`) | review queue | Assumptions below full confidence, waiting for a person |
| review decision | approval | A person's answer, stored as their annotation; it outranks every agent's |
| `open_items` | open items | What waits on an action: a required annotation, a load, a measurement |

## Wider words

- **Ontology** names what agents establish: entities, relationships,
  terms. The declared level is the harness schema.
- **Semantic layer** names the metrics, dimensions and time grains,
  served as views.
- **Harness** names the whole: the schema, the measurements, the
  tests, the review and the next steps around an agent.
- **Data tests** (dbt), **expectations** (Great Expectations),
  **checks** (Soda), **assertions** (DataHub) and **monitors**
  (observability tools) all name what a test is here.
- **Data observability** names watching freshness, volume, schema and
  lineage; here the stale rule, each load's row count, and the lineage
  of every view and load.
- **Data contract** names a producer's promise about a table: its
  schema, keys and quality rules; here a kit's required properties and
  the tests on a source's tables.
