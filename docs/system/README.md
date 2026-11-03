# System

The server: one binary, one workspace, three doors. How it is built is
[`../architecture/`](../architecture/README.md); the shipped surface is
[`../reference/`](../reference/README.md); running it is
[`../start/`](../start/README.md).

## What stands

- **The statement spine** — the parser over its corpus acceptance
  suite; every fixture transcribes a real artifact.
- **The record** — the gloss extension's store: every declared
  relation a table of rows in the lake's catalog; supersession is a
  read; admission, grain and the stale rule
  ([store](../architecture/store.md)).
- **The engine** — one DuckDB instance per process, a channel per
  call bound to its actor and dataset; the reads as SQL over the
  record and the lake ([reads](../reference/reads.md)).
- **Import** — file sources read at the source, `PROBE` rehearsing a
  recipe and `IMPORT` landing it again in one commit; a database the
  engine attaches as a relational source.
- **The kits** — the vocabulary, the quality screens, the metrics and
  the futures as SQL, run at every open; the model service named once
  for the walk, the forecast and the what-if, `GLOSSQL_SERVICE_URL`
  ([functions](../reference/functions.md),
  [methods](../methods/README.md)).
- **The doors** — `/<dataset>/mcp` and `/mcp` (one `glossql` tool,
  stateless, row cap; the dataset's door opens every call on it, the
  workspace's opens unbound), `/<dataset>/query` (streaming Arrow IPC), `/<dataset>/app`
  (the docket as the dataset's page: what waits on a person and the
  ruling form, the metrics, the quality of the data, the lineage,
  every table and read as CSV or Parquet; the glossed apps beside it)
  ([doors](../reference/doors.md)). The dataset is the resource and the
  doors are protocols over it: a call arrives already bound, no door
  keeps a cursor. The actor is the bearer token's subject, verified
  against the issuer's published keys; the actor kind is the door's
  (the `mcp` doors agent, the rest human); what a kind may *do* beyond that is
  governance, still held open.
- **Skills** — one skill per `skills/*/SKILL.md`, where a
  door-connected agent learns the language. The MCP door serves each
  as a resource (`skill://<name>/SKILL.md`), as a prompt of the same
  name, and as a row of the `pages()` read, with the language spec and
  grammar beside them as `doc://` resources; every skill is gated by
  the server's test suite like these pages.
- **Open** — a workspace receives the kits at every open, declared
  only where the record holds none of them; declaration relations
  read as plain tables.

## Known limits

- No request timeouts — bounded at PoC scale.
- An MCP session reaped between calls answers a bare `Not Found`; the
  client re-inits and replays `USE`.
