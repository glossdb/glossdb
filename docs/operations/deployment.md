# Deployment

In production glossdb runs as one container. The lake's catalog is on
Postgres and its files are in an object store. People and agents sign
in through your identity provider.

## The container

The image is `ghcr.io/glossdb/glossdb:<version>`, x86_64, built at
each release. `docker build .` in a checkout builds the same.

It holds the binary, the DuckDB library, the glossql extension, the
kits and the lake's DuckDB extensions, on a distroless base with no
shell. It carries no model. It listens on `0.0.0.0:8080` and runs as
an unprivileged user.

```bash
docker run --rm -p 8080:8080 \
  -e GLOSSDB_ISSUER=https://issuer.example \
  -e GLOSSDB_AUDIENCE=https://glossdb.example \
  -e GLOSSDB_CLIENT_ID=… -e GLOSSDB_CLIENT_SECRET=… \
  -e GLOSSDB_CATALOG_SQL=postgres://glossdb:…@db.example:5432/glossdb \
  -e GLOSSDB_WAREHOUSE=s3://lake/warehouse \
  -e GLOSSDB_WAREHOUSE_KEY_ID=… -e GLOSSDB_WAREHOUSE_SECRET=… \
  -e GLOSSDB_WAREHOUSE_REGION=eu-central-1 \
  ghcr.io/glossdb/glossdb:0.3.0
```

The configuration is the environment; the image reads no file. Each
variable: [configuration](../reference/configuration.md).

- The server serves plain HTTP. Terminate TLS in front of it and set
  the HTTPS URL as `GLOSSDB_AUDIENCE`.
- `GET /healthz` answers `ok` without sign-in, for the platform's
  probe.
- The image sets `GLOSSDB_MEMORY_LIMIT=6144` and
  `GLOSSDB_SPILL_LIMIT=6144` (megabytes), sized for a machine with
  8 GiB of memory and 8 GiB of disk. Set your own on another machine.
- Run one server per workspace. The server keeps the workspace's
  summary in its own process.

## Sizing

Measured on a laptop, one server, the workspace on local disk. These
are measurements, not guarantees; a deployment on Postgres and an
object store adds the network to each.

| What | Data | Measured |
|---|---|---|
| one MCP call | Formula 1, 200 metrics, 1.3M rows, 10M rows | 0.14 to 0.22 s; most of it plans `next` |
| a write that computes nothing | Formula 1 | 0.22 s |
| a table view over three tables, defined | Formula 1 | 1.14 s, 30 results computed after the write |
| one metric's page in the console, its frames | Formula 1, 200 metrics, 1.3M rows, 10M rows | 0.12 to 0.35 s |
| peak memory for one metric's page | 10M rows | about 1.5 GB above idle |

## The lake

| | Laptop | Deployment |
|---|---|---|
| Catalog | `catalog.ducklake` in the `--workspace` directory | the Postgres database `GLOSSDB_CATALOG_SQL` names |
| Files | `warehouse/` in that directory, Parquet | the bucket `GLOSSDB_WAREHOUSE` names (`s3://`, `gs://`) |
| State | the directory | the database and the bucket |

A container has no workspace directory: without both variables the
server does not start and names them. The catalog holds the loaded
tables' versions and the `glossql_*` tables: annotations,
measurements, tests, load history. Back up the database and the
bucket together.

A `gs://` bucket named without a key pair is reached as the service
account the platform runs the server as.

## Sign-in

glossdb is an OAuth 2.1 resource server. It verifies tokens against
the keys your identity provider publishes. It issues no tokens and
keeps no user table. Any OpenID Connect provider works.

1. Register the server as an API whose identifier is
   `GLOSSDB_AUDIENCE`.
2. Register one confidential application (`GLOSSDB_CLIENT_ID`,
   `GLOSSDB_CLIENT_SECRET`) with two redirect URIs:
   `<audience>/auth/callback` for the browser, and the loopback
   redirect of the MCP client that signs in with it.
3. Set `GLOSSDB_ISSUER` to the provider's issuer URL.

A token is signed with RS256, ES256, ES384 or EdDSA, names its key
(`kid`), and carries `iss`, `sub`, `exp` and an `aud` naming the
audience. MCP clients ask for that audience with the RFC 8707
`resource` parameter, so the provider has to honour it. A request
without a valid token gets a 401. A server that cannot reach its
issuer does not start.

**Who writes.** The token's subject is the actor. The MCP paths write
as an agent; the console and the query endpoint write as a person. A
person's value outranks an agent's at each read
([review and decide](../usage/review.md)).

**Engine settings.** `SET`, `ATTACH`, `INSTALL`, `LOAD` and `CALL` are
open only to the actor ids `GLOSSDB_ROOT` names.

Access per user and table is planned. Today each signed-in actor
reads and writes the whole workspace.

## Logs and traces

The server logs JSON lines to stdout. At the default level, `info`, a
call is logged with its actor, its dataset and the digest and length
of its statement text. The text itself is logged at `debug` only,
because statements carry data. A refusal is logged with its reason,
without the token.

- `GLOSSDB_LOG` sets the level (`debug`) or a `tracing` filter
  (`glossdb_duck=debug,rmcp=debug`).
- `OTEL_EXPORTER_OTLP_ENDPOINT` names an OpenTelemetry collector
  (`http://127.0.0.1:4318`). The server then also exports spans as
  traces and events as logs, over OTLP. `OTEL_EXPORTER_OTLP_PROTOCOL`
  is `http/protobuf` (the default) or `grpc`.

## The model service

A kit's function can call a model service, named as
`GLOSSDB_SERVICE_URL`. No shipped kit calls one. Without it such a
call is refused by name and the rest works.
