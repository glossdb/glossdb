# Documentation

glossdb is a harness framework for data agents, written in the
[glossql](https://github.com/glossdb/glossql) language. Every page here
is also served to agents over MCP as a `doc://docs/…` resource.

## Overview

- [Introduction](overview/introduction.md): what glossdb is and why.
- [How it works](overview/how-it-works.md): the data harness beside the
  coding harness, part by part.
- [Terms](overview/terms.md): every word, beside the industry's.

## Getting started

- [Installation](getting-started/installation.md)
- [Connect an agent](getting-started/connect.md)
- [Quickstart](getting-started/quickstart.md): from raw exports to
  served metrics in one session.

## Usage

- [Workspaces and datasets](usage/workspaces.md)
- [Loading data](usage/loading-data.md)
- [Describing tables and columns](usage/describing-data.md)
- [Relationships](usage/relationships.md)
- [Metrics](usage/metrics.md)
- [Measurements](usage/measurements.md)
- [Data tests](usage/data-tests.md)
- [The review queue](usage/review.md)
- [The console](usage/console.md)
- [Data apps](usage/data-apps.md)
- [Querying and export](usage/querying.md)

## Operations

- [Configuration](operations/configuration.md)
- [Authentication](operations/authentication.md)
- [Deployment](operations/deployment.md)
- [Logging and monitoring](operations/monitoring.md)

## Reference

- [Statements](reference/statements.md)
- [Functions](reference/functions.md)
- [Views and table functions](reference/reads.md)
- [The KPI kit](reference/kpi-kit.md)
- [The MCP interface](reference/mcp.md)
- [HTTP endpoints](reference/http.md)
- [App authoring](reference/apps.md)

The language itself: [SPEC.md](https://github.com/glossdb/glossql/blob/main/SPEC.md)
and [grammar.ebnf](https://github.com/glossdb/glossql/blob/main/grammar.ebnf).

## Extending

- [Kits](extending/kits.md)
- [Goals and next steps](extending/next-steps.md)

## Methods

How each measurement computes its result, and its limits:
[relationship discovery](methods/discovery.md),
[join coherence](methods/coherence.md),
[derivations](methods/derivations.md),
[stock or flow](methods/behavior.md),
[the judge](methods/judge.md).

## Preview

These need a model service and may change.

- [Forecasts](preview/forecasts.md)
- [Expected ranges](preview/expected-ranges.md)
- [Plans](preview/plans.md)
- [Scenarios](preview/scenarios.md)

## Internals

For contributors: [the kernel](internals/kernel.md),
[the catalog store](internals/catalog.md),
[storage](internals/storage.md),
[DuckDB and the extension](internals/duckdb.md).
