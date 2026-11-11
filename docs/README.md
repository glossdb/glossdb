# glossdb documentation

glossdb is the data harness for people and agents. Agents build a
company's data intelligence layer in the lake, beside the data.
glossdb tests what they state against the data at each load, and a
person reviews and decides. Source data goes in; described and tested
tables, single values and metrics come out.

The MCP interface serves each page here as `doc://docs/<path>`.

## Start

- [Installation](getting-started/installation.md): the binary, the
  image, a build from source.
- [Quickstart](getting-started/quickstart.md): two CSV files to a
  tested table, a single value and a metric.

## The work, step by step

| Step | Page |
|---|---|
| Connect | [Connect and load](usage/load.md): sources, load queries, loads |
| Describe | [Describe](usage/describe.md): annotations, relationships, the business glossary |
| Serve | [Define views](usage/views.md): a table, a single value, a metric |
| Test | [Test](usage/test.md): the built-in tests, your own tests, states |
| Decide | [Review and decide](usage/review.md): the review queue and review decisions |
| Serve | [Serve and read](usage/serve.md): SQL, Arrow, export, the console, data apps |
| Preview | [Forecasts, expected ranges, plans and scenarios](usage/outlook.md) |

## Operate and extend

- [Deployment](operations/deployment.md): the container, the lake,
  sign-in, logs.
- [Kits](extending/kits.md): add annotations, measurements and tests
  for a use case.

## Reference

- [Interfaces](reference/interfaces.md): MCP, the query endpoint, the
  paths, the statements the server refuses.
- [Reads](reference/reads.md): each catalog table, view and table
  function with its columns.
- [Configuration](reference/configuration.md): flags and variables.
- [App authoring](reference/apps.md): the parts and tiles of a data
  app.

The language is specified in `doc://SPEC.md` and `doc://grammar.ebnf`,
served from the glossql extension the server bundles.

## Status of each feature

| Feature | Status |
|---|---|
| Sources, load queries, datasets, annotations, measurements, tests | stable |
| Views, metric series, `next`, review decisions | stable |
| MCP interface, query endpoint, console, data apps, export | stable |
| Semantic model and lineage export | stable |
| Forecasts, expected ranges, plans, scenarios | preview |
| Reading a lake in place; dbt and semantic-model import; access per user | planned |
