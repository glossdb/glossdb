# Architecture

glossdb has a small fixed core: what it takes to load data into a
dataset, serve its metrics, and keep the catalog about it. Around the
core sits a fixed set of questions the core asks of the outside. Each
question is an extension point, answered by something outside. The core
owns the question, the shape of the answer, and who reads the answer.
The outside party owns the answer and nothing else.

Two kinds of party answer:

- a **driver** turns what is not rows into rows;
- a **service** turns rows into rows.

Both attach on the server. An agent learns nothing new when an
extension point is filled: it sees a declaration in a kit, a step in
the `next` read, and a page.

## The core

- **The language and the catalog.** The glossql extension: the grammar
  on DuckDB's parser, the catalog tables, declarations, annotations,
  measurements, the newest value per author as a read, and the stale
  rule ([the catalog](catalog.md)).
- **The engine and the lake.** DuckDB and a DuckLake: the catalog as
  rows, Parquet under the warehouse, a snapshot per write
  ([DuckDB seams](duckdb.md), [storage](storage.md)).
- **Sources and load queries.** File sources read by the engine's own
  readers, relational sources the engine attaches; `PREVIEW`, `IMPORT`,
  one load query per table.
- **Metrics.** A metric is a view. Its columns carry the vocabulary,
  and the time grains on its period column say how its periods are
  walked. Four reads serve it: `metric_series()`, `metric_axes()`,
  `fact_values()` and `metric_sources()`
  ([views and table functions](../reference/reads.md)).
- **Tests and review.** Tests (`DECLARE TEST`), detectors, `TESTS()`, the
  review queue, and review decisions taken in the console.
- **Interfaces and the console.** The two MCP interfaces, the query
  endpoint, and the console with the data apps
  ([MCP interface](../reference/mcp.md),
  [HTTP endpoints](../reference/http.md)).
- **Next steps.** Eight goals, each with its steps, composed at open
  from the kits' steps and the core's; the two lines every result ends
  with ([next steps](../extending/next-steps.md)).
- **The kits.** Below.

The core is complete without any service. It answers from the
customer's data alone.

## The kits

A kit is SQL: declarations and table macros the engine runs at every
open, in order ([kits](../extending/kits.md)). Four ship, two from the
extension's `kits/` and two from this repository's:

- **The KPI kit** (the extension's `kits/kpi`): the vocabulary. What a
  column means, its role, its additivity, its unit, which columns slice
  a metric, what a table is, the source conventions, the business
  glossary; the two column profilers; the detector that scores the
  vocabulary's values; the tests that bind them.
- **The quality kit** (the extension's `kits/quality`): what the data
  is like and how it holds together. The screens over a dataset's cells
  and the measurements that read them: hierarchies, relationships and
  their coherence, derivations, metric definition collisions, the
  temporal profile.
- **The metrics kit** (`kits/metrics` here): time grains, the metric
  summary row, the cells, single values, lineage; the built-in tests
  and the test report per metric in `next`.
- **The outlook kit** (`kits/outlook` here, preview): expected ranges,
  forecasts, plan judgments and scenario estimates, each a measurement;
  the `bands` and `plan` goals.

The kits are part of the core, not add-ons: the `next` read and the
console name their aspects and functions. A workspace's own vocabulary
stays the agent's work: metrics, data tests, scenarios and plans,
declared over MCP.

## Drivers

A driver turns something that is not rows into rows. The rows are the
interface: a load query loads them, typed by the load query, versioned
on every import
([SPEC.md §3](https://github.com/glossdb/glossql/blob/main/SPEC.md)).

Available:

- **Files.** Parquet, CSV and JSON under a source's location, read by
  the engine's own readers. `PREVIEW` runs the load query's SQL at the
  source and loads nothing.
- **Relational databases.** A database the engine attaches: Postgres,
  MySQL, SQLite, DuckDB. The load query reads its tables through the
  attachment.

Planned: workbooks, read in process, a sheet as a table and the
workbook's definitions as rows; documents, read by a processing
service, a PDF or a slide deck as passages, one row each. A new kind of
source is a new `type` in SPEC §3, tested against real artifacts first.

## Services

A service turns rows into rows. An extension point works like this:

1. **Declared in a kit.** An aspect holds the shape of the answer. A
   measurement asks the question.
2. **Answered by the service the deployment names.** The core sends
   rows as JSON. The service answers with rows.
3. **Refused by name when none is named.** The read says what to set,
   and start-up logs it. Nothing stands in for a missing service.

The model service is named once per instance, `GLOSSDB_SERVICE_URL`
([configuration](../operations/configuration.md)). The outlook kit
calls its routes through the extension's `glossql_service`: expected
ranges, forecasts and what-if. Every answer names the service and its
version, and the measurement stores it as `served_by`.

Two rules hold for every service:

- **A service never writes the catalog.** It returns rows. The core
  stores them as a measurement, like any function's result.
- **Meaning stays in the core.** Additivity, grain, the calendar and
  the data version are decided here. The service decides nothing about
  what the numbers mean.

## The agent's side

Any agent that speaks MCP drives glossdb through one tool, the skills
and the pages ([MCP interface](../reference/mcp.md)). Nothing extends
here. A filled extension point reaches the agent as a declaration it
reads in the catalog, a step in the `next` read, and a page.

## The code

The server is a Cargo workspace of three crates:

- **`duck`** is the engine: the facade the interfaces use over the
  glossql extension and a DuckLake, and the actor types a call is
  stamped with. The catalog's own reads and the interfaces' reads are
  the core and goals kits under `kits/`.
- **`apps`** serves the console and the data apps.
- **`serverd`** is the binary with its interfaces.

The language belongs to the extension: SPEC.md, `grammar.ebnf` and the
corpus live in its repository, and the server serves the two documents
from the extension's share. The kits are SQL loaded at open, each one
skipped when its text is the one the lake already recorded: core,
metrics, outlook and door from `kits/` here, around the extension's
`kpi` and `quality` kits. `kits/README.md` says what they add.

## Known limits

- No request timeouts.
- An MCP session closed between calls answers a bare `Not Found`. The
  client starts a new session and sends `USE` again.
