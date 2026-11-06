# glossdb

**A harness framework for data agents.** Declare what must be known about
your data. Agents establish it — the semantic layer, the ontology, the
quality record — and answer from it.

## Why agents get data wrong

Agents hallucinate on company data because of information asymmetry. The
meaning is not in the rows: a column called `amount` does not say whether
it is net of tax, a balance or a movement, or which currency it is in, and
no query fails when the agent guesses. Coding agents have it easier: code
carries most of its own meaning, and compilers and tests say when the
agent is wrong. Data has neither. glossdb gives data both: a declared
description the agent must complete, and measurements and checks that
test it.

## How it works

1. **You declare the harness.** Aspects are its schema: the properties
   each dataset, table, column and relationship must carry, each with a
   JSON Schema. Measurements produce evidence, witnesses check what is
   said, goals set the work, and grants say which actor may do what. All
   of it is written in [glossql](https://github.com/glossdb/glossql) and
   packaged as kits.
2. **Agents establish what must be known.** Before a table serves a
   metric, the agent glosses it: what one row is, each column's role,
   each measure's additivity and unit, the joins, the metric definitions.
   A gloss is an assertion, validated against its aspect's schema and
   stored with its actor and the data version it describes.
3. **Evidence, not guesses.** Measurements profile the data, discover
   relationships and hierarchies, and test derivations and stock-or-flow
   behaviour. Each result is versioned with the data it read and
   recomputed only when that data changes.
4. **What is known is served back.** Every tool call returns what happened
   and what is still open; what is known about any table is one query
   away; skills teach the vocabulary. Nothing depends on the chat history.
5. **Progress is measured.** Every required aspect nobody has glossed is
   an open item. Goals turn open items into next steps, and coverage,
   conflicts, failing checks and open questions are the agent's score.
   Where the data cannot answer, the agent asks a person, and the answer
   closes the gap for every later query.

## What ships

**glossql**, the language and its catalog:

- aspects with JSON Schemas, kinds (asserted, computed, metric) and
  conditions for when they are required;
- glosses validated on write, kept per actor, versioned with the data,
  and marked stale when the data under them changes;
- measurement functions in SQL, stored with their provenance and reused
  until their inputs change;
- witnesses and detectors that score agreement between agents, people
  and measurements;
- metric definitions as SQL views, with their assumptions and confidence;
- load queries (recipes) over files and attached databases; every load a
  DuckLake snapshot with its row account and column lineage;
- the `kpi` kit, the semantic layer's vocabulary: role, additivity, unit,
  dimension, entity, the business glossary;
- the `quality` kit: relationship and hierarchy discovery, join coverage,
  derivation tests, time coverage, stock-or-flow evidence, tolerance
  checks.

**glossdb**, the harness around it:

- an MCP interface: one tool for glossql and SQL, the skills served as
  resources and prompts, every result closing with where the work stands;
- goals (structure, metrics, slices, checks, apps, review), each with
  what is done, what is open, and the next statement, filled from the
  catalog;
- a review queue: assumptions below full confidence become questions,
  answered in the console or in the agent's client;
- the semantic layer's query interface: a metric's series by time grain,
  its slices along dimensions, what moved;
- the console: the review queue, metrics, quality, the catalog with a page
  per table, column and aspect, lineage, export, and a query pane;
- data apps that agents write over the metrics, stored in the catalog;
- Arrow over HTTP and CSV or Parquet export for tools; sign-in through
  your identity provider;
- one binary with DuckDB in process; a DuckLake on Postgres and object
  storage in production, a directory on a laptop.

**Preview:** forecasts, expected ranges, plans and scenarios on the
metrics, through a model service.

**Planned:** grants per actor on statements and datasets, as in SQL.

## Other harnesses

The same framework declares harnesses for other jobs: harmonising several
sources into one target model, a data contract per source, a documented
feature set for modelling. The `spatial` kit is a small working example:
it requires a shape and a coordinate system on every geometry column, and
measures the geometries.

## Actors and grants

Actors are agents, people, or a person working with an agent. Grants work
as in SQL: an architect declares the harness schema; an onboarding agent
loads sources into one dataset; an analyst agent glosses and measures it
without declaring anything new; a reviewer answers the questions; a BI
tool reads the views.

## Getting started

On a Mac:

```bash
brew install glossdb/glossdb/glossdb
GLOSSDB_INSECURE_OPEN=true glossdb --workspace ~/acme    # a laptop try-out: no sign-in
claude mcp add --transport http glossdb http://127.0.0.1:8080/mcp
```

Then ask the agent to land a folder of exports and describe it; the
console is at `http://127.0.0.1:8080/<dataset>/app`. On Linux, run the
image `ghcr.io/glossdb/glossdb`. Sign-in through an identity provider,
the deployment shape (a Postgres catalog and an object store) and every
setting: [install](docs/start/install.md). Claude, ChatGPT and other MCP
clients: [connect](docs/start/connect.md). One session from raw exports
to served metrics: [walkthrough](docs/start/walkthrough.md).

## Interfaces

One process, one listener:

| Path | For | Serves |
|---|---|---|
| `/mcp` | agents | the workspace: sources are declared and datasets brought into being here, and `USE` picks the dataset on every call |
| `/<dataset>/mcp` | agents | one dataset: every call opens on it |
| `/<dataset>/query` | tools | a query in the request body, an Arrow IPC stream back |
| `/<dataset>/app` | people | the console and the data apps; every table and metric as CSV or Parquet |
| `/` | people | the workspace: its datasets and the way into each |

The MCP interface has one tool, `glossql`, which takes glossql and SQL
statements. The skills that teach the language and the kits are served as
MCP resources (`skill://<name>/SKILL.md`) and as prompts, with the
language's `SPEC.md` and `grammar.ebnf` beside them as `doc://`
resources. Everything live is read through the language: the declared
vocabulary, functions, witnesses and glosses are plain tables.

A bearer token from the workspace's identity provider says who is
speaking: the server verifies it against the provider's published keys,
and the token's subject is the actor. The interface sets the actor's
kind: the MCP paths are agents', the others people's.

## Building from source

A Rust workspace. `cargo build -p glossdb-serverd` builds the server;
use `--release` to run it for real. DuckDB is compiled into the
binary from the sources its Rust crate ships, about three minutes
once per profile; the glossql extension is built from the sibling
checkout `../gloss` (`GEN=ninja make release`, a C++ build of DuckDB
that takes a while once), or named by `GLOSSQL_EXTENSION` and
`GLOSSQL_KITS` ([install](docs/start/install.md)). The parallel build
needs memory; if the build dies without a compiler error, the OOM
killer hit — common in memory-capped containers. Bound the
parallelism to about one job per 2 GB of available memory:

```
cargo build --release -j4    # or CARGO_BUILD_JOBS=4
```

The dev profile already trims debug info workspace-wide (the workspace
`Cargo.toml` records why); even a single job needs ~4 GB free for the
largest units, DuckDB's among them.

## Repository layout

- `crates/` — the server, a Cargo workspace: `duck` (the engine: DuckDB
  with the glossql extension and a DuckLake, behind one facade), `apps`
  (the console and the data apps), `serverd` (the binary and its
  interfaces).
- `kits/` — the server's kits, SQL loaded at open around the extension's
  `kpi` and `quality`: `core` (the workspace's own vocabulary and the
  catalog's reads), `metrics` (the semantic layer's query interface),
  `futures` (preview), `door` (what is open, and the goals); each with
  its test suite ([kits](kits/README.md)).
- `skills/` — the skills served to agents.
- `docs/` — [start](docs/start/README.md),
  [concepts](docs/concepts/README.md),
  [reference](docs/reference/README.md),
  [methods](docs/methods/README.md),
  [architecture](docs/architecture/README.md).
- `corpus/` — the two transcriptions behind the server's kits.
- `vendor/` — DuckDB's SQL guide for the pinned release, served to
  agents.

The language — `SPEC.md`, `grammar.ebnf`, and the corpus that holds
every construct to a real artifact — lives with the extension in
[glossdb/glossql](https://github.com/glossdb/glossql);
`crates/duck/glossql.ref` pins the commit a build carries.

## Status

A working proof-of-concept. `cargo test` at the workspace root is the
standing invariant: every fenced example under `docs/` and `skills/`
parsed and bound on the engine, the interface suites, and the suites
beside the kits under `kits/`; the extension's kits carry theirs in its
repository. The language is a working draft. Grammar changes are
corpus-first: a construct is only added together with a fixture that
was checked against a real artifact.

## The name

A *gloss* is a marginal annotation explaining a text's meaning; a
glossary is a collection of them. `GLOSS` is the write verb — you gloss
an aspect onto a subject; `GLOSSARY()` is the read.

## Prior art

- [ggsql](https://github.com/posit-dev/ggsql) — grammar-of-graphics clauses as a SQL
  extension; the pattern for a declarative tail on SELECT.
- [Snowflake semantic views](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view) —
  declared semantics as SQL objects consumed by agents; declarations only, no
  evidence model.
- [Open Semantic Interchange / Apache Ossie](https://github.com/open-semantic-interchange/osi) —
  vendor-neutral interchange for semantic models; a possible export mapping for the
  vocabulary tier.
- [DuckLake](https://ducklake.select/) — lakehouse design: parquet data files, all
  metadata in a transactional SQL database; a persistence reference point.

None of these carry adjudicated context: measurements, agent
assertions, and human assertions in separate slots per subject and
aspect, with disagreement shown as a band instead of silently
resolved. This language treats that as first-class.
