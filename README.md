# glossdb

**The data harness for people and agents.** Agents build a company's
data intelligence layer in the lake, beside the data. glossdb tests
what they state against the data at each load, and a person can review
and decide.

## Data intelligence

Data intelligence is what a company knows about its data: what it
means, how its sources map, whether it can be trusted, and who
decides. It is the layer under BI and AI. Answers, data apps and
forecasts sit on top of it.

glossdb builds that layer with two properties:

- **The glossary is stored in the lake.** Annotations, relationships,
  view definitions, tests and review decisions are tables beside the
  data, in a DuckLake. A description belongs to a version of the data:
  it reads `stale` once a load redefines, retypes or drops its column,
  and a measurement once the tables it read change.
- **Statements about the data are tested.** A unit, a key, a
  measure's additivity, a join: each is checked against the data, and
  checked again after each load.

In practice glossdb is data middleware. Source data goes in. Described
and tested tables, single values and metrics come out, readable by any
tool that opens the lake. It is for data engineers and data leaders
who build and run that layer. Harmonising several systems of record is
the first use case. glossdb works beside dbt, semantic layers, catalogs
and lakes, in their formats.

## The five steps

1. **Connect.** Declare a source. A load query (`DECLARE RECIPE`)
   brings a table into a dataset. Each load is a snapshot with its row
   count and column lineage.
2. **Describe.** Annotate (`GLOSS`) each table, column and
   relationship: meaning, role, unit, additivity. Each annotation is
   validated against a JSON Schema on write and stored with its author
   and the data version.
3. **Test.** A test is a statement about the data with a state: green,
   yellow, orange or red. Each metric gets built-in tests for join
   fan-out, referential integrity and additivity. A test brings its
   finding and the statement that fixes it.
4. **Decide.** An assumption in a view definition that a person should
   confirm goes to the review queue. The person's decision is stored
   and outranks the agent's annotation.
5. **Serve.** A view is named SQL on a dataset, read as
   `FROM <dataset>.<name>`: a table, a single value or a metric. The
   semantic model is served as an Apache Ossie document and the
   lineage as OpenLineage events.

`next` lists a dataset's open work by these steps; every MCP result
ends with its count and first row.

## Getting started

On a Mac:

```bash
brew install glossdb/glossdb/glossdb
GLOSSDB_INSECURE_OPEN=true glossdb --workspace ~/acme    # a laptop try-out, no sign-in
claude mcp add --transport http glossdb http://127.0.0.1:8080/mcp
```

Ask the agent to load a folder of exports and describe it. The console
is at `http://127.0.0.1:8080/<dataset>/app`. On Linux, run the image
`ghcr.io/glossdb/glossdb`.

One session from two CSV files to a tested table, a single value and
a metric: [quickstart](docs/getting-started/quickstart.md). Production:
[deployment](docs/operations/deployment.md). Everything else:
[the documentation](docs/README.md).

## Interfaces: one process, one port

| Path | For | Serves |
|---|---|---|
| `/mcp` | agents | the workspace; `USE <dataset>;` binds a call |
| `/<dataset>/mcp` | agents | one dataset; each call opens on it |
| `/<dataset>/query` | tools | statements in, an Arrow IPC stream or JSON out |
| `/<dataset>/app` | people | the console, the data apps, CSV and Parquet export |
| `/` | people | the workspace's datasets |

The MCP interface has one tool, `glossql`, for glossql statements and
SQL, and serves the skills (`skill://`), the docs and the language
(`doc://`) and the open work (`next://`) as resources
([interfaces](docs/reference/interfaces.md)).

## Status at release 0.3.0

| Feature | Status |
|---|---|
| Sources, load queries, annotations, measurements, tests, review decisions | stable |
| Views (tables, single values, metrics), metric series, `next` | stable |
| The MCP interface, the query endpoint, the console, data apps, export | stable |
| Semantic model (Apache Ossie) and lineage (OpenLineage) export | stable |
| Sign-in through an identity provider | stable |
| Forecasts, expected ranges, plans, scenarios (need a model service) | preview |
| Reading a lake in place; dbt and semantic-model import; access per user | planned |

## Building from source

A Rust workspace: `crates/` (the server), `kits/` (the server's kits,
[kits](kits/README.md)), `skills/` (the skills served to agents),
`docs/`, `corpus/` (two examples the suite parses) and `vendor/`
(DuckDB's SQL guide, served to agents). `cargo build -p
glossdb-serverd` builds the server with DuckDB compiled in; the
glossql extension comes from the sibling checkout `../gloss`
([installation](docs/getting-started/installation.md)). `cargo test`
runs every suite, and parses and binds each fenced example under
`docs/` and `skills/`. The language lives with the extension in
[glossdb/glossql](https://github.com/glossdb/glossql).

## License

Apache 2.0.
