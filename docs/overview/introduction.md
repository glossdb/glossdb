# Introduction

glossdb is a harness framework for data agents. You declare what must
be known about your data. Agents establish it — the semantic layer,
the ontology, the quality record — and answer from it.

## Why

Agents get company data wrong because the meaning is not in the rows.
A column called `amount` does not say whether it is net of tax, a
balance or a movement, or which currency it is in, and no query fails
when an agent guesses. glossdb makes the agent write that meaning
down, checks it against the data, and serves it back on every call.

## What you get

- **A harness schema.** Declare the properties every dataset, table,
  column and metric must carry, each with a JSON Schema.
- **Annotations with provenance.** Every value an agent or a person
  writes is validated, stored with its author and tied to the data
  version it describes.
- **Measurements and tests.** SQL functions profile the data and find
  keys, joins and hierarchies; tests score where measurements, agents
  and people disagree.
- **A semantic layer.** Metric definitions are SQL views, served by
  time grain and dimension.
- **A review queue.** Assumptions below full confidence go to a person;
  the answer outranks every agent's.
- **Next steps.** Every result over MCP ends with the test report:
  per metric its worst test and the statement that settles it, then
  the review queue.
- **A console** for people, an **MCP server** for agents, and **Arrow
  over HTTP** for tools — one binary with DuckDB inside, on a DuckLake.

glossdb is written in [glossql](https://github.com/glossdb/glossql),
the language for writing data harnesses, a DuckDB extension.

## Where next

- [How it works](how-it-works.md): the harness, part by part.
- [Installation](../getting-started/installation.md) and
  [quickstart](../getting-started/quickstart.md).
- [Terms](terms.md): every word, beside the industry's.
