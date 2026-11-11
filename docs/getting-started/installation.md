# Installation

glossdb is one binary, `glossdb`, serving one workspace: a DuckLake
and what is declared over it. DuckDB, the glossql extension and the
kits ship with it.

## macOS

On Apple Silicon:

```bash
brew install glossdb/glossdb/glossdb
```

## Linux

Run the container image `ghcr.io/glossdb/glossdb:<version>` (x86_64),
or build from source. The image and its settings:
[deployment](../operations/deployment.md).

## Try it on a laptop

```bash
GLOSSDB_INSECURE_OPEN=true glossdb --workspace ~/acme
```

The server listens on `127.0.0.1:8080`. The workspace directory holds
the whole state: `catalog.ducklake`, the lake's catalog, and
`warehouse/`, the loaded tables as Parquet files. Both are created if
missing.

`GLOSSDB_INSECURE_OPEN=true` serves each interface without sign-in and
records each caller as `insecure_dev_mode`. Use it to try the server
out, not in a deployment. Sign-in through an identity provider:
[deployment](../operations/deployment.md#sign-in).

## Connect an agent

Any MCP client with the streamable HTTP transport works. With Claude Code and
sign-in off:

```bash
claude mcp add --transport http glossdb http://127.0.0.1:8080/mcp
```

`/mcp` serves the workspace; `/<dataset>/mcp` opens each call on one
dataset. With sign-in on, the client signs in as the application the
server is registered as:

```bash
MCP_CLIENT_SECRET=$GLOSSDB_CLIENT_SECRET claude mcp add --transport http \
  --client-id $GLOSSDB_CLIENT_ID --client-secret --callback-port 3118 \
  glossdb http://127.0.0.1:8080/mcp
claude mcp login glossdb
```

The callback port is the loopback redirect the provider's application
lists (`http://localhost:3118/callback`).

People open `http://127.0.0.1:8080/` in a browser: the workspace's
datasets, and the console of each at `/<dataset>/app`.

## Build from source

The server links DuckDB and loads the glossql extension. A source
build takes the extension, its kits and the language's two documents
from the sibling checkout `../gloss`, at the commit
`crates/duck/glossql.ref` names, built there with `GEN=ninja make
release`. The server's own kits come from `kits/`.

```bash
cargo run --release -p glossdb-serverd -- --workspace ~/acme
```

`GLOSSQL_EXTENSION`, `GLOSSQL_KITS` and `GLOSSDB_KITS` name other
places ([configuration](../reference/configuration.md)). A run with
`--workspace` reads `.env` from the working directory; `.env.example`
lists the sign-in settings.

## What happens at start

The server opens the lake, replaces the catalog's views, and runs the
kits in order: `core`, the extension's `kpi` and `quality`, `views`,
`outlook`, `goals`. A kit the lake already recorded with the same text
runs nothing. Then it listens.
