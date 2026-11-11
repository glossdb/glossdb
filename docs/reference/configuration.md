# Configuration

glossdb reads flags and environment variables once, at start. A run
with `--workspace` also reads `.env` from the working directory; a set
variable wins over the file. A deployment reads no file.

## Flags

Each flag but `--workspace` has a variable; the flag wins.

| Flag | Variable | Default | Meaning |
|---|---|---|---|
| `--workspace <dir>` | | | the directory that holds the lake's catalog and files. Required unless both `GLOSSDB_CATALOG_SQL` and `GLOSSDB_WAREHOUSE` are set |
| `--addr <ip:port>` | `GLOSSDB_ADDR` | `127.0.0.1:8080` | where the server listens |
| `--row-cap <n>` | `GLOSSDB_ROW_CAP` | `200` | rows an MCP data read returns before it says `truncated` |
| `--memory-limit <megabytes>` | `GLOSSDB_MEMORY_LIMIT` | DuckDB's own | the engine's memory ceiling |
| `--spill-limit <megabytes>` | `GLOSSDB_SPILL_LIMIT` | DuckDB's own | the disk the engine may spill onto |
| `--version`, `--help` | | | print and exit |

## Sign-in

| Variable | Meaning |
|---|---|
| `GLOSSDB_ISSUER` | the identity provider's issuer URL |
| `GLOSSDB_AUDIENCE` | this server's own URL: the `aud` a token must name, and the host the MCP interface answers beside loopback. Default `http://<addr>` |
| `GLOSSDB_CLIENT_ID`, `GLOSSDB_CLIENT_SECRET` | the application registered at the issuer; the browser sign-in uses the secret |
| `GLOSSDB_INSECURE_OPEN` | the literal `true` serves each interface without sign-in and records each caller as `insecure_dev_mode`. For a laptop |
| `GLOSSDB_ROOT` | actor ids, comma-separated, that may run `SET`, `ATTACH`, `INSTALL`, `LOAD` and `CALL`. Empty by default |

Without `GLOSSDB_INSECURE_OPEN=true`, the issuer, the client id and
the client secret are required; the server names the one that is
missing and does not start.

## The lake

| Variable | Meaning |
|---|---|
| `GLOSSDB_CATALOG_SQL` | the lake's catalog on a Postgres server (`postgres://user:password@host:5432/db`). Unset: `catalog.ducklake` in the workspace directory |
| `GLOSSDB_WAREHOUSE` | the lake's files in an object store (`s3://bucket/prefix`, `gs://bucket/prefix`). Unset: `warehouse/` in the workspace directory |
| `GLOSSDB_WAREHOUSE_KEY_ID`, `GLOSSDB_WAREHOUSE_SECRET` | the object store's key pair, set together. Unset with a `gs://` bucket: the platform's service account |
| `GLOSSDB_WAREHOUSE_REGION` | the bucket's region, for S3 |

## The model service (preview)

| Variable | Meaning |
|---|---|
| `GLOSSDB_SERVICE_URL` | the model service for forecasts, expected ranges and scenarios. Unset: those measurements are refused by name |
| `GLOSSDB_SERVICE_TOKEN` | the bearer token the service expects |
| `GLOSSDB_SERVICE_AUDIENCE` | on Google Cloud, instead of a token: the server mints an ID token for this audience as the service account it runs as |

## Logs

| Variable | Meaning |
|---|---|
| `GLOSSDB_LOG` | a level (`debug`) or a `tracing` filter. `RUST_LOG` is read when it is unset; the default is `info` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | an OpenTelemetry collector to export traces and logs to. Unset: no export |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` (default) or `grpc` |

## Where the pieces are

A released binary finds the extension, the kits and DuckDB's
extensions in `share/glossdb` beside it. A source build takes them
from the sibling checkout and `kits/`. These name other places:

| Variable | Names |
|---|---|
| `GLOSSQL_EXTENSION` | the glossql extension file |
| `GLOSSQL_KITS` | the extension's kits; `SPEC.md` and `grammar.ebnf` are read from beside them |
| `GLOSSDB_KITS` | the server's kits |
| `GLOSSQL_EXTENSION_DIR` | DuckDB's own extensions (ducklake, httpfs, postgres) |
