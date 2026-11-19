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

## The five functions of data intelligence

Each function answers one question about the data. The pages are
grouped by it.

| Function | The question | Page |
|---|---|---|
| Integration | Which sources map? | [Connect and load](usage/load.md): sources, load queries, loads. [Define views](usage/views.md): a table, a single value, a metric |
| Metadata | What does this mean? | [Describe](usage/describe.md): annotations, relationships, the business glossary |
| Quality | Can we trust this value? | [Test](usage/test.md): the built-in tests, your own tests, states |
| Governance | Who decides and may use it? | [Review and decide](usage/review.md): the review queue and review decisions |
| Lineage | Where does this come from? | [Read the views](usage/read.md): column lineage, OpenLineage events, and how the views are read: SQL, Arrow, export, the console, data apps |

## The four kinds of work

The work on a dataset is of four kinds: integrate (connect a source,
load tables, define views), describe, test and review (an open
question goes to a person; the decision is kept). They are kinds of
work, not stages. A view needs a loaded table, a test needs
something defined, and a review needs an open question. Lineage
results from the other four, and a view can be queried once it is
defined. `next` labels each open row with its kind and a level: what
must be done (served data is wrong or cannot be served), what should
(the layer is incomplete for what is served) and what could
([reads](reference/reads.md)).

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
- [How results stay current](reference/dependencies.md): what a
  stored result read, what puts it out of date, and who computes it
  again.
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
| Forecasts, expected ranges, plans, scenarios | planned |
| Reading a lake in place; dbt and semantic-model import; access per user | planned |
