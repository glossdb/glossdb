# Deployment

In production glossdb runs as one container, with the lake's catalog
on Postgres and its files in an object store.

## The container

The image is `ghcr.io/glossdb/glossdb:<version>`, x86_64, pushed at
each release. `docker build .` in a checkout builds the same; with
`--build-arg GH_TOKEN=<a GitHub token>` the extension comes from its
pipeline's build instead of a compile.

The base is distroless: glibc, the C runtime libraries and the root
certificates, with no shell and no package manager. The image holds the
binary, the DuckDB library, the extension, the kits and the lake's
extensions; no model, no weights, no GPU. It listens on 8080 and runs
as the base's unprivileged `nonroot` user.

A container has no workspace directory. Its state is the catalog and
the data files `GLOSSDB_CATALOG_SQL` and `GLOSSDB_WAREHOUSE` name;
without both the server refuses to start and names them. The
configuration is the environment the platform injects, secrets
included; the image reads no file and holds no value of its own.

```bash
docker run --rm -p 8080:8080 \
  -e GLOSSDB_ISSUER=https://issuer.example \
  -e GLOSSDB_AUDIENCE=https://glossdb.example \
  -e GLOSSDB_CLIENT_ID=… -e GLOSSDB_CLIENT_SECRET=… \
  -e GLOSSDB_CATALOG_SQL=postgres://glossdb:…@db.example:5432/glossdb \
  -e GLOSSDB_WAREHOUSE=gs://lake/warehouse \
  -e GLOSSDB_WAREHOUSE_KEY_ID=… -e GLOSSDB_WAREHOUSE_SECRET=… \
  -e GLOSSDB_SERVICE_URL=https://… -e GLOSSDB_SERVICE_TOKEN=… \
  ghcr.io/glossdb/glossdb:0.3.0
```

`GET /healthz` answers `ok` without sign-in, for the platform's probe,
and is not logged as a call.

Every setting: [configuration](configuration.md). Sign-in:
[authentication](authentication.md).

## Sizing

The image is sized for a machine with 8 GiB of memory and an 8 GiB
ephemeral disk: `GLOSSDB_MEMORY_LIMIT=6144` for the engine, the rest
of the memory for the process; `GLOSSDB_SPILL_LIMIT=6144` for the
disk, the rest for the writable layer. It listens on `0.0.0.0:8080`.
On a different machine, set your own numbers as variables.

## One server per workspace

One server owns a workspace: it keeps the catalog reads in memory, so a
deployment runs one replica per catalog and warehouse
([the catalog](../internals/catalog.md)).

## The workspace

On a laptop the workspace is a directory:

```
acme/
  catalog.ducklake   the lake's catalog: every loaded table's versions
                     and files, in the shapes the DuckLake
                     specification names, and every glossql table beside
                     them (absent with GLOSSDB_CATALOG_SQL: all of it is
                     then on that Postgres server)
  warehouse/         the lake's files: every loaded table as Parquet,
                     one directory per dataset and table
```

The directory is the complete, copyable state of the system.

With `GLOSSDB_CATALOG_SQL` and `GLOSSDB_WAREHOUSE` set, the catalog and
`warehouse/` move to that Postgres server and that object store; the
state is then that database and that bucket, and the server runs
without a directory. Either way it is a plain DuckLake, readable by any
DuckLake client. More: [storage](../internals/storage.md).

## The model service

Expected ranges, forecasts and scenarios (preview) are served by a
model service, hosted or run beside the server, named once as
`GLOSSDB_SERVICE_URL`. The binary carries no model. Without the
service those measurements refuse by name and everything else works.
