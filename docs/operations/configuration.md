# Configuration

glossdb takes its settings from flags and environment variables.
Every flag but `--workspace` has a variable named after it; the flag
wins where both are set.

A run with `--workspace` also reads `.env` in the working directory,
and the environment on top of it: a set variable wins over the file. A
deployment reads no file; its platform injects the variables, secrets
included.

## Flags

| Flag | Variable | Default | Meaning |
|---|---|---|---|
| `--workspace <dir>` | — | required when the catalog or the data files live in it | the directory holding the lake's catalog and its files. A deployment names both in the environment and runs without a directory |
| `--addr <ip:port>` | `GLOSSDB_ADDR` | `127.0.0.1:8080` | where the server listens |
| `--row-cap <n>` | `GLOSSDB_ROW_CAP` | `200` | rows an MCP tool result returns before it says `truncated`. Data reads only; catalog reads arrive whole |
| `--memory-limit <megabytes>` | `GLOSSDB_MEMORY_LIMIT` | the engine's own, most of the machine | the engine's memory ceiling. A sort or a hash aggregate that outgrows it spills to the temporary directory, up to `--spill-limit` |
| `--spill-limit <megabytes>` | `GLOSSDB_SPILL_LIMIT` | the engine's own | how much disk the engine may spill onto, under the system's temporary directory |

## Variables

| Variable | Meaning |
|---|---|
| `GLOSSDB_ROOT` | actor ids, comma-separated, that may use the engine's own settings over the interfaces: `SET`, `ATTACH`, `INSTALL`, `LOAD`, `CALL`. Everyone else has the workspace: tables, rows, files, views, the language, the catalog |
| `GLOSSDB_ISSUER` | the identity provider's issuer URL ([authentication](authentication.md)) |
| `GLOSSDB_AUDIENCE` | this server's canonical URI: the API identifier registered at the issuer, the `aud` a token must name (RFC 8707 §2), and the host the MCP interface answers beside loopback. Read with sign-in off too, so a deployment always names its URL. Defaults to `http://<addr>` |
| `GLOSSDB_CLIENT_ID` | the application registered at the issuer for this server; the browser sign-in uses it |
| `GLOSSDB_CLIENT_SECRET` | that application's secret, used by the browser sign-in |
| `GLOSSDB_INSECURE_OPEN` | `true` (the literal) serves every interface without sign-in. No issuer is needed, no sign-in is served, and every caller is recorded as `insecure_dev_mode`. For a laptop, never a deployment |
| `GLOSSDB_CATALOG_SQL` | the lake's catalog on a Postgres server (`postgres://user:password@host:5432/db`) instead of the workspace's own file. Unset, `catalog.ducklake` in the workspace serves |
| `GLOSSDB_WAREHOUSE` | the lake's files in an object store instead of under `--workspace`: `s3://bucket/prefix` or `gs://bucket/prefix`, reached through DuckDB's `httpfs` with the key pair below. A `gs://` bucket named without the pair is reached as the service account the platform runs the server as (Cloud Run, GKE, Compute Engine): the token is minted from the metadata server before the lake opens and again before it expires. With this and `GLOSSDB_CATALOG_SQL` set, the server needs no workspace directory |
| `GLOSSDB_WAREHOUSE_KEY_ID`, `GLOSSDB_WAREHOUSE_SECRET` | the object store's key pair, together: S3's access key and secret, or the HMAC pair of a Google service account. Held in DuckDB's secret manager, scoped to the warehouse, never logged |
| `GLOSSDB_WAREHOUSE_REGION` | the bucket's region, for S3 |
| `GLOSSDB_SERVICE_URL` | the model service's address, for the preview features: expected ranges, forecasts, scenarios. Each call's route is appended. Unset, those measurements refuse by name and everything else works |
| `GLOSSDB_SERVICE_TOKEN` | the bearer the model service expects, sent as-is |
| `GLOSSDB_SERVICE_AUDIENCE` | instead of a token, on GCP: the service's URL. The server mints a Google-signed ID token for it from the metadata server, as the service account it runs as, and refreshes it before it expires |
| `GLOSSQL_EXTENSION`, `GLOSSQL_KITS`, `GLOSSDB_KITS` | where the glossql extension file, the extension's kits and the server's kits are, when not beside the binary in `share/glossdb` and not the source tree's. `SPEC.md` and `grammar.ebnf`, served over MCP, are read from beside the extension's kits |
| `GLOSSDB_LOG` | the log filter ([monitoring](monitoring.md)) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | an OpenTelemetry collector to export to ([monitoring](monitoring.md)) |
