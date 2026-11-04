# Install and run

`glossdb` is one binary serving one workspace — the directory that
holds your data lake and everything declared over it. The binary
carries no model. The walk, the forecast and the what-if are served
by a model service the deployment names once, `GLOSSDB_SERVICE_URL`,
hosted or run beside the server. Unnamed, those three refuse by name
and everything else serves.

## Install

macOS (Apple Silicon):

```bash
brew install glossdb/glossdb/glossdb
```

The formula installs one command, `glossdb`, with the DuckDB library,
the glossql extension and the kits beside it. On Linux, run the
container (below) or build from source.

## Build and start

The server links DuckDB and loads the glossql extension, built from its
own repository at the commit `crates/duck/glossql.ref` names. A source
build takes the extension, its kits and the language's two documents
from the sibling checkout, `../gloss`, built there with `GEN=ninja
make release`, and the server's own kits from `kits/`;
`GLOSSQL_EXTENSION`, `GLOSSQL_KITS` and `GLOSSDB_KITS` name other places.

```bash
cp .env.example .env            # then fill it in — see Tokens below
cargo run --release -p glossdb-serverd -- --workspace ~/acme
```

The server reads `.env`, reads the issuer's keys, opens the lake,
prints its doors and listens:

```
2026-09-03T08:04:42.103275Z  INFO verifying tokens issuer=https://issuer.example audience=http://127.0.0.1:8080 application=a1b2c3…
2026-09-03T08:04:42.104551Z  INFO glossdb listening — / (datasets), /mcp, /<dataset>/mcp, /<dataset>/query, /<dataset>/app addr=127.0.0.1:8080 scheme="http"
```

## The container

The same binary as an x86_64 image: `ghcr.io/glossdb/glossdb:<version>`,
pushed at each release tag. `docker build .` at a checkout builds the
same. A distroless base — glibc, the C runtime libraries, the root
certificates, no shell and no package manager — the binary, the
DuckDB library beside it, the extension, the kits and the lake's
extensions; no model, no weights, no GPU. It listens on 8080 and runs
as the base's unprivileged `nonroot` user. There is no workspace in a
container: the state is the catalog and the warehouse
`GLOSSDB_CATALOG_SQL` and `GLOSSDB_WAREHOUSE` name, and without both
the server refuses to start, naming them; the apps are the built-ins
and the app parts in the record. The configuration is the environment
the platform injects, secrets included — nothing is read from a file,
and the image holds no value of its own. `GET /healthz` answers `ok`
outside the gate, for a platform's probe, and stays off the record.
One server owns a workspace: it holds the record read in memory, so a
deployment runs one replica per catalog and warehouse
([the store](../architecture/store.md)).

```bash
docker run --rm -p 8080:8080 \
  -e GLOSSDB_ISSUER=https://issuer.example \
  -e GLOSSDB_AUDIENCE=https://glossql.example \
  -e GLOSSDB_CLIENT_ID=… -e GLOSSDB_CLIENT_SECRET=… \
  -e GLOSSDB_CATALOG_SQL=postgres://glossql:…@db.example:5432/glossql \
  -e GLOSSDB_WAREHOUSE=gs://lake/warehouse \
  -e GLOSSDB_WAREHOUSE_KEY_ID=… -e GLOSSDB_WAREHOUSE_SECRET=… \
  -e GLOSSDB_SERVICE_URL=https://… -e GLOSSDB_SERVICE_TOKEN=… \
  ghcr.io/glossdb/glossdb:0.3.0
```

The image sizes the server for a box with 8 GiB of memory and an
8 GiB ephemeral disk: `GLOSSDB_MEMORY_LIMIT=6144` for the engine's
ceiling, the rest of the memory to the process; `GLOSSDB_SPILL_LIMIT=6144`
for the disk, the rest to the writable layer. It listens on
`0.0.0.0:8080`. A different box injects its own numbers as variables,
beside the rest of its environment.

## Flags

Every flag but `--workspace` has a variable named after it, and the
flag wins where both are set.

| flag | variable | default | meaning |
|---|---|---|---|
| `--workspace <dir>` | — | required when the catalog or the warehouse lives in it | the laptop's shape: the directory holding the lake's catalog and its files. A deployment names both in the environment and runs without a directory |
| `--addr <ip:port>` | `GLOSSDB_ADDR` | `127.0.0.1:8080` | where the doors listen |
| `--row-cap <n>` | `GLOSSDB_ROW_CAP` | `200` | rows an MCP tool result ships before declaring `truncated` (data reads only; the record's reads arrive whole) |
| `--memory-limit <megabytes>` | `GLOSSDB_MEMORY_LIMIT` | the engine's own, most of the box | the engine's memory ceiling. A sort or a hash aggregate that outgrows it spills to the temporary directory, up to `--spill-limit` |
| `--spill-limit <megabytes>` | `GLOSSDB_SPILL_LIMIT` | the engine's own | how much of the disk the engine may spill onto, under the system's temporary directory. The disk's own number, set from the box |
| — | `GLOSSDB_ROOT` | nobody | the actor ids, comma-separated, that have the engine's own knobs at the doors: `SET`, `ATTACH`, `INSTALL`, `LOAD`, `CALL`. Everyone else has the workspace: tables, rows, files, views, the language, the reads |

Authorization is not a flag. A run with a workspace reads `.env` in
the working directory, and the environment on top of it (a set
variable wins over the file); a deployment reads no file — its
platform injects the variables, secrets included:

| variable | meaning |
|---|---|
| `GLOSSDB_ISSUER` | the authorization server's issuer URL; its OpenID configuration names the keys tokens are verified against |
| `GLOSSDB_AUDIENCE` | this server's canonical URI: the API identifier registered at the issuer and the `aud` a token must name (RFC 8707 §2), and the host the agent door answers beside loopback — read under the open switch too, so a deployment always names its URL; defaults to `http://<addr>` |
| `GLOSSDB_CLIENT_ID` | the application registered at the issuer for this server, which the browser login on `/app` signs in and exchanges its code as |
| `GLOSSDB_CLIENT_SECRET` | that application's secret, used by the browser login on `/app` |
| `GLOSSDB_INSECURE_OPEN` | `true` (the literal) serves every door without authentication — no issuer needed, no login served, every caller recorded as `insecure_dev_mode` with the door's standing. The name is the warning: a laptop trying the server out, never a deployment |
| `GLOSSDB_CATALOG_SQL` | the lake's catalog on a Postgres server (`postgres://user:password@host:5432/db`) instead of the workspace directory's own file — the same catalog in a database that outlives a container. Unset, `catalog.ducklake` in the workspace serves |
| `GLOSSDB_WAREHOUSE` | the lake's files in an object store instead of under `--workspace`: `s3://bucket/prefix` or `gs://bucket/prefix`, reached through the engine's `httpfs` extension with the key pair below. A `gs://` bucket named without the pair is reached as the service account the platform runs the server as (Cloud Run, GKE, Compute Engine): the access token is minted from the metadata server before the lake opens and minted anew before it expires, no key anywhere. With both this and `GLOSSDB_CATALOG_SQL` named the server needs no workspace directory |
| `GLOSSDB_WAREHOUSE_KEY_ID`, `GLOSSDB_WAREHOUSE_SECRET` | the store's key pair, together: S3's access key and secret, or the HMAC pair of a Google service account. Held in the engine's secret manager, scoped to the warehouse, never logged |
| `GLOSSDB_WAREHOUSE_REGION` | the bucket's region, for S3 |
| `GLOSSDB_SERVICE_URL` | the model service's address; each call's route is appended — the walk, the forecast, the what-if. Unnamed, those measurements refuse by name and everything else serves |
| `GLOSSDB_SERVICE_TOKEN` | the bearer the service expects: a key it was started with, sent as-is |
| `GLOSSDB_SERVICE_AUDIENCE` | instead of a token, on GCP: the service's URL. The server mints a Google-signed ID token for it from the metadata server, as the service account it runs as, and refreshes it before it expires — no key anywhere |
| `GLOSSQL_EXTENSION`, `GLOSSQL_KITS`, `GLOSSDB_KITS` | where the glossql extension file, the extension's kits and the server's own kits are, when not beside the binary in `share/glossdb` and not the dev tree: the sibling checkout's build and `kits/`. `SPEC.md` and `grammar.ebnf`, served on the door, are read from beside the extension's kits |
| `GLOSSDB_LOG` | what the server puts on its record — a `tracing` filter. A bare level (`debug`) is this server's crates at that level, the libraries at `info` and the MCP library at `warn`; directives (`glossdb_duck=debug,rmcp=debug`) are taken as written. `RUST_LOG` is honoured when it is unset; `info` when neither is |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | where an OpenTelemetry collector listens (`http://127.0.0.1:4318`; `/v1/traces` and `/v1/logs` are appended). Set, the record is also exported there — spans as traces, events as logs, OTLP, batched. Unset, nothing is exported. The exporter's other variables are the SDK's own: `OTEL_EXPORTER_OTLP_PROTOCOL` picks the transport, `http/protobuf` (the default) or `grpc`; `OTEL_EXPORTER_OTLP_HEADERS` carries a hosted collector's credentials; `OTEL_RESOURCE_ATTRIBUTES` names the deployment beyond `service.name=glossdb` |

`.env.example` at the repository root lists them; `.env` is never
committed.

The record goes to stdout: lines for a person when that is a
terminal, JSON otherwise. At `info` the server logs a request at any
door as its method, path and status, and a call as its actor, the
dataset it arrived on, the digest and length of its text, and the
spans of the work it caused — each statement, each read, each
landing, each measurement run — each closing with its busy and idle
time. The text of a call is a `debug` event inside its span and
nothing else, because statement bodies and groundings carry data. A
refusal carries its reason and never the token.

With `OTEL_EXPORTER_OTLP_ENDPOINT` set the same record goes to the
collector as well, under `service.name=glossdb`: the spans as traces,
with their events; the events as log records, each carrying the trace
and span id it happened under, so a log line leads to its trace. A
`traceparent` header a client sends makes its request a child of the
client's trace. The export runs on the OpenTelemetry SDK's own
threads, never on the engine's, and is flushed when the server stops
on SIGINT or SIGTERM. Metrics are not exported: a backend derives
request rates and latencies from the spans.

## Tokens

The token's subject says who is speaking. The door sets the standing:
the `mcp` doors write as an agent, the other doors as a human. glossdb
is an OAuth 2.1 resource server and never an authorization server — it
verifies against the keys the issuer publishes, it does not issue, and
there is no login flow, client registration or user table inside a
workspace. A request without a valid token gets a 401, and a server
without an issuer does not start. The one exception is explicit:
`GLOSSDB_INSECURE_OPEN=true` serves the doors open, every caller
recorded as `insecure_dev_mode` — for a laptop trying the server out,
never for a deployment.

The issuer is any OpenID Connect provider. Register this server there
as an API whose identifier is `GLOSSDB_AUDIENCE`, and one confidential
application (`GLOSSDB_CLIENT_ID`) with two redirect URIs:
`<audience>/auth/callback` for the browser login, and the loopback
redirect of the MCP client that will sign in with it (Claude Code:
`http://localhost:3118/callback`, see [`connect.md`](connect.md)). The
provider's discovery document
(`<issuer>/.well-known/openid-configuration`) is everything the server
needs. Tokens must be RS256, ES256/384 or EdDSA, name their key
(`kid`), and carry `iss`, `sub`, `exp`.

A token binds to this server by its `aud` naming the audience. MCP
clients ask for that with the RFC 8707 `resource` parameter, so the
issuer must honour it — register the audience as a resource the
issuer can mint for; that is the whole setup. The server refuses a
token that names another resource, or none.

How a client obtains a token is the client's flow with the issuer —
[`connect.md`](connect.md) shows Claude Code's.

## What open does

Opening a workspace loads the extension, installs and loads the lake's
extensions, attaches the lake — creating the catalog file and the
`warehouse/` directory if absent — and declares the record's own
reads. Then it runs the kits in order, the KPI kit and the quality
kit from the extension, the metrics kit and the futures kit from
`kits/`: ordinary declarations, readable
back through the `aspects`, `functions` and `witnesses` relations like
anything an agent writes, declared only where the record holds none
of them. Last it declares the door's reads and composes the `next`
read from every kit's routes. The server writes nothing outside the
workspace directory.

## Workspace anatomy

```
acme/
  catalog.ducklake   the lake's catalog and the record — every landed
                     table's versions and files in the shapes the
                     DuckLake specification names, and every declared
                     relation as a table beside them (absent with
                     GLOSSDB_CATALOG_SQL: all of it is then on the
                     Postgres server it names)
  warehouse/         the lake's files — every landed table as parquet,
                     one directory per dataset and table
```

The workspace directory is the complete, copyable state of the
system: the catalog and the record in one file, the landed tables'
files beside it.

With `GLOSSDB_CATALOG_SQL` and `GLOSSDB_WAREHOUSE` set, the catalog
and `warehouse/` move to the Postgres server and the object store they
name: the state of the system is then that database and that
warehouse, and a deployment runs without a directory. Everything else
is the same lake, readable by any DuckLake client.
