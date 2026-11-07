# Installation

glossdb is one binary, `glossdb`, serving one workspace: the data lake
and everything declared over it. DuckDB, the glossql extension and the
kits ship with it.

## macOS

On Apple Silicon:

```bash
brew install glossdb/glossdb/glossdb
```

The formula installs the `glossdb` command with the DuckDB library,
the glossql extension and the kits beside it.

## Linux

Run the container image `ghcr.io/glossdb/glossdb:<version>`, or build
from source. The image and its settings:
[deployment](../operations/deployment.md).

## Try it on a laptop

Start the server on a workspace directory, with sign-in turned off:

```bash
GLOSSDB_INSECURE_OPEN=true glossdb --workspace ~/acme
```

The server listens on
`127.0.0.1:8080`. `GLOSSDB_INSECURE_OPEN=true` serves every interface
without sign-in and records every caller as `insecure_dev_mode`: use it
to try the server out, never in a deployment. To sign in through your
identity provider instead, see [authentication](../operations/authentication.md).

Then connect an agent: [connect](connect.md).

## Build from source

The server links DuckDB and loads the glossql extension, built from its
own repository at the commit `crates/duck/glossql.ref` names. A source
build takes the extension, its kits and the language's two documents
from the sibling checkout `../gloss`, built there with `GEN=ninja make
release`, and the server's own kits from `kits/`. `GLOSSQL_EXTENSION`,
`GLOSSQL_KITS` and `GLOSSDB_KITS` name other places.

```bash
cp .env.example .env            # then fill it in: see authentication
cargo run --release -p glossdb-serverd -- --workspace ~/acme
```

The server reads `.env`, fetches the issuer's keys, opens the lake,
prints its interfaces and listens:

```
2026-09-03T08:04:42.103275Z  INFO verifying tokens issuer=https://issuer.example audience=http://127.0.0.1:8080 application=a1b2c3…
2026-09-03T08:04:42.104551Z  INFO glossdb listening — / (datasets), /mcp, /<dataset>/mcp, /<dataset>/query, /<dataset>/app addr=127.0.0.1:8080 scheme="http"
```

## What happens at start

Opening a workspace loads the extension, installs and loads the lake's
extensions, and attaches the lake, creating the catalog file and the
`warehouse/` directory if they are missing. It declares the catalog's
own views, then runs the kits in order: the KPI kit and the quality
kit from the extension, then the server's metrics and futures kits.
Kits are ordinary declarations, readable through the `aspects`,
`functions` and `tests` tables like anything an agent writes, and
a kit the catalog already holds runs nothing. Last, the server declares
its own views and composes the `next` view from every kit's next steps
([next steps](../extending/next-steps.md)). The server writes nothing
outside the workspace.

What the workspace directory holds: [deployment](../operations/deployment.md#the-workspace).
