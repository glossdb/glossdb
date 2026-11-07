# glossdb

**A harness framework for data agents.** Declare what must be known
about your data. Agents establish it — the semantic layer, the
ontology, the quality record — and answer from it.

Coding agents work inside a harness: types, a compiler, tests, CI and
review tell them when they are wrong. Data agents have none of this.
glossdb gives them one, built inside the database, on the live data and
its versions.

## Why agents get data wrong

The meaning of company data is not in the rows. A column called
`amount` does not say whether it is net of tax, a balance or a
movement, or which currency it is in. No query fails when an agent
guesses. Code carries most of its own meaning, and compilers and tests
catch the rest. Data has neither, so agents answer with confidence and
without the facts.

## How it works

1. **You declare the harness.** The harness schema lists what must be
   known about each dataset, table, column, relationship and metric,
   each property with a JSON Schema. Kits package it per domain.
2. **Agents annotate the data.** Before a table serves a metric, the
   agent states what one row is, each column's role, each measure's
   unit and additivity, the joins, and the metric definitions. Every
   annotation is validated on write and stored with its author and the
   data version it describes.
3. **Measurements and tests check what is said.** Functions profile
   the data, find keys, joins and hierarchies, and test derivations and
   stock-or-flow behaviour. Tests score where measurements, agents and
   people disagree. Results are tied to the data version they read and
   go stale when it changes.
4. **What is known is served back.** What is known about any table is
   one query away. Every tool call ends with the next steps. Nothing
   depends on the chat history.
5. **People decide what the data cannot.** An assumption below full
   confidence goes to a review queue. A person's answer is stored and
   outranks every agent's.

How each part maps onto a coding harness: [how it
works](docs/overview/how-it-works.md). Every word: [terms](docs/overview/terms.md).

## Features

**The catalog**, written in [glossql](https://github.com/glossdb/glossql):

- a harness schema of properties with JSON Schemas, required by
  condition (a unit on every measure column);
- annotations validated on write, kept per author, versioned with the
  data, marked stale when the data under them changes;
- measurement functions in SQL, stored with their provenance and reused
  until their inputs change;
- tests that score agreement between measurements, agents and people;
- metric definitions as SQL views, with their assumptions and
  confidence;
- load queries over files and attached databases; every load a
  DuckLake snapshot with its row count and column lineage;
- the `kpi` kit, the semantic layer's vocabulary: role, additivity,
  unit, dimension, entity, the business glossary;
- the `quality` kit: relationship and hierarchy discovery, join
  coverage, derivation tests, time coverage, stock-or-flow evidence,
  tolerance checks.

**The server**:

- an MCP server with one tool for glossql and SQL, the skills served as
  resources and prompts, every result ending with the next steps;
- goals per dataset (structure, metrics, slices, checks, apps, review),
  each with what is done, what is open, and the next statement;
- a review queue, answered in the console or in the agent's client;
- the semantic layer's queries: a metric's series by time grain, its
  slices by dimension, what moved;
- the console: the review queue, metrics, quality, a page per table,
  column and property, lineage, export, and a query pane;
- data apps that agents write over the metrics, stored in the catalog;
- Arrow over HTTP and CSV or Parquet export; sign-in through your
  identity provider;
- one binary with DuckDB in process; a DuckLake on Postgres and object
  storage in production, a directory on a laptop.

## Status

Release 0.3.0.

| Feature | Status |
|---|---|
| The catalog, annotations, measurements, tests | stable |
| The `kpi` and `quality` kits | stable |
| The MCP server, goals and next steps | stable |
| The semantic layer: metrics, series, slices | stable |
| The review queue and the console | stable |
| Data apps, Arrow over HTTP, export | stable |
| Sign-in through an identity provider | stable |
| Forecasts, expected ranges, plans, scenarios (through a model service) | preview |
| Grants per actor on statements and datasets | planned |

## Other harnesses

The same framework declares harnesses for other jobs: harmonising
several sources into one target model, a data contract per source, a
documented feature set for modelling. The `spatial` kit is a small
working example: it requires a shape and a coordinate system on every
geometry column, and measures the geometries.

## Actors and grants

Actors are agents, people, or a person working with an agent. Grants
work as in SQL: an architect declares the harness schema; an onboarding
agent loads sources into one dataset; an analyst agent annotates and
measures it without declaring anything new; a reviewer answers the
questions; a BI tool reads the views.

## Getting started

On a Mac:

```bash
brew install glossdb/glossdb/glossdb
GLOSSDB_INSECURE_OPEN=true glossdb --workspace ~/acme    # a laptop try-out: no sign-in
claude mcp add --transport http glossdb http://127.0.0.1:8080/mcp
```

Ask the agent to load a folder of exports and describe it. The console
is at `http://127.0.0.1:8080/<dataset>/app`. On Linux, run the image
`ghcr.io/glossdb/glossdb`.

- Sign-in, the production setup (a Postgres catalog and an object
  store) and every setting: [deployment](docs/operations/deployment.md),
  [configuration](docs/operations/configuration.md).
- Claude, ChatGPT and other MCP clients: [connect](docs/getting-started/connect.md).
- One session from raw exports to served metrics:
  [quickstart](docs/getting-started/quickstart.md).

## Interfaces

One process, one port:

| Path | For | Serves |
|---|---|---|
| `/mcp` | agents | the workspace: declare sources and create datasets; `USE` picks the dataset per call |
| `/<dataset>/mcp` | agents | one dataset: every call opens on it |
| `/<dataset>/query` | tools | a query in the request body, an Arrow IPC stream back |
| `/<dataset>/app` | people | the console and the data apps; every table and metric as CSV or Parquet |
| `/` | people | the workspace: its datasets and the way into each |

The MCP server has one tool, `glossql`, which takes glossql and SQL
statements. The skills that teach the language and the kits are MCP
resources (`skill://<name>/SKILL.md`) and prompts; the language's
`SPEC.md` and `grammar.ebnf` are served beside them as `doc://`
resources. Everything live is plain tables, read through the language.

A bearer token from the workspace's identity provider names the actor.
The server verifies it against the provider's published keys. The MCP
paths are agents'; the others are people's.

## Building from source

A Rust workspace. `cargo build -p glossdb-serverd` builds the server;
add `--release` to run it for real. DuckDB is compiled into the binary
(about three minutes once per profile). The glossql extension is built
from the sibling checkout `../gloss` (`GEN=ninja make release`), or
named by `GLOSSQL_EXTENSION` and `GLOSSQL_KITS`
([installation](docs/getting-started/installation.md)).

The parallel build needs memory. If it dies without a compiler error,
the OOM killer hit. Allow about one job per 2 GB:

```
cargo build --release -j4    # or CARGO_BUILD_JOBS=4
```

`cargo test` at the workspace root runs every suite: every fenced
example under `docs/` and `skills/` is parsed and bound on the engine,
the interfaces are tested end to end, and each kit's suite runs beside
it.

## Repository layout

- `crates/` — the server: `duck` (DuckDB with the glossql extension
  and a DuckLake, behind one facade), `apps` (the console and the data
  apps), `serverd` (the binary and its interfaces).
- `kits/` — the server's kits, loaded at open around the extension's
  `kpi` and `quality`: `core`, `metrics`, `futures` (preview), `door`
  (goals and next steps); each with its test suite
  ([kits](kits/README.md)).
- `skills/` — the skills served to agents.
- `docs/` — the [documentation](docs/README.md): getting started,
  usage, operations, reference, extending, methods, internals.
- `corpus/` — real artifacts written in glossql, behind the server's
  kits.
- `vendor/` — DuckDB's SQL guide for the pinned release, served to
  agents.

The language lives with the extension in
[glossdb/glossql](https://github.com/glossdb/glossql);
`crates/duck/glossql.ref` pins the version a build carries.

## License

Apache 2.0.
