# The business information kernel

glossdb is a kernel. A small core is hard-wired: what it takes to land
data for a dataset, serve its metrics and keep the record about it.
Around the core sits a fixed set of questions the core asks of the
outside. Each question is an extension point. Something outside
answers it. The core owns the question, the shape of the answer, and
who reads the answer. The outside party owns the answer and nothing
else.

Two kinds of party answer. A **driver** turns what is not rows into
rows. A **service** turns rows into rows. Both attach on the server.
The agent at the door learns nothing new when a point is filled: it
sees a declaration in a kit, an arm in the next read, and a page.

## The core

- **The language and the record.** The glossql extension: the grammar
  on DuckDB's parser, the store, declarations, glosses, measurements,
  supersession as a read, the stale rule ([store](store.md)).
- **The engine and the lake.** DuckDB, and a DuckLake: the catalog as
  rows, parquet under the warehouse, a snapshot per write
  ([substrate](substrate.md), [storage](storage.md)).
- **Sources and recipes.** File sources read by the engine's own
  readers, relational sources the engine attaches; probe, import, a
  recipe per table.
- **The metrics.** A metric is a view; its columns carry the
  vocabulary; the ladder on its period column says how its periods
  are walked; the four reads `metric_series()`, `metric_axes()`,
  `fact_values()` and `metric_sources()` ([reads](../reference/reads.md)).
- **Checks and rulings.** Witnesses, detectors, `ATTEST()`, the
  question round, the ruling at the app door.
- **The doors and the docket.** The two agent doors, the Arrow door,
  the app door with the built-in docket and the glossed apps
  ([doors](../reference/doors.md)).
- **The next read.** Eight goals, a route of arms per goal, composed
  at open from the kits' routes and the core's; the two lines on every
  result.
- **The kits.** Below.

The core is whole without any service. It answers from the customer's
data alone.

## The kits

A kit is SQL: declarations and table macros the engine runs at every
open, in order. Four ship, two from the extension's `kits/` and two
from this repository's:

- **The KPI kit** (the extension's `kits/kpi`): the vocabulary. What a column means,
  its role, how a measure behaves, its unit, which columns slice, what
  a table is, the source conventions, the definitions handbook; the
  two column profilers; the detector that scores the vocabulary's
  voices; the witnesses that bind them.
- **The quality kit** (the extension's `kits/quality`): what the data is like and how
  it holds together. The screens over a dataset's cells and the
  measurements that read them: hierarchies, relationships, their
  coherence, derivations, grounding collisions, the temporal profile.
- **The metrics kit** (`kits/metrics` here): the ladder, the fact row, the
  cells, the facts, the lineage; the metrics and slices goals.
- **The futures kit** (`kits/futures` here): the walk's bands, the
  forecast, the plan's judgement, the scenario's estimate, each a
  measurement; the bands and plan goals.

The kits are core content, not an extension. The next read and the
docket name their aspects and functions. A workspace's own vocabulary
stays the agent's work: metrics, validations, scenarios, plans,
declared at the door.

## Drivers

A driver turns something that is not rows into rows. The rows are the
interface: a recipe lands them, typed by the recipe, versioned on
every import ([SPEC.md §3](https://github.com/glossdb/glossql/blob/main/SPEC.md)).

Today:

- **Files.** Parquet, CSV and JSON under a source's location, read by
  the engine's own readers; `PROBE` runs the recipe's SQL at the
  source and lands nothing.
- **Relational databases.** A database the engine attaches: Postgres,
  MySQL, SQLite, DuckDB. The recipe reads its tables through the
  attachment.

Planned: workbooks, read in process, a sheet as a table and the
workbook's definitions as rows; documents, read by a processor
service, a PDF or a slide deck as passages, one row each. A new kind
of source is a new `type` in SPEC §3. The corpus comes first.

## Services

A service turns rows into rows. The pattern of a point:

1. **Declared in a kit.** An aspect holds the shape of the answer. A
   measurement asks the question.
2. **Filled by the service the deployment names.** The core sends
   rows as JSON. The service answers rows.
3. **Refused by name when none is named.** The read says what to set.
   Start-up logs it. Nothing stands in for a missing service.

The model service is named once for the instance, `GLOSSDB_SERVICE_URL`
([install](../start/install.md)), and the futures kit calls its routes
through the extension's `glossql_service`: the walk, the forecast, the
what-if. Every answer names the service and its version, and the
measurement records it as `served_by`.

Two rules hold for every service:

- **A service never writes the record.** It returns rows. The core
  lands them as a measurement, like any function's result.
- **Semantics stay in the core.** The behaviour, the grain, the
  calendar and the pin are decided here. The service decides nothing
  about what the numbers mean.

## The door

Any agent that speaks MCP drives the kernel through one tool, the
skills and the pages ([doors](../reference/doors.md)). Nothing
extends here. A filled point reaches the agent as a declaration it
reads in the record, an arm in the next read, and a page the door
serves.
