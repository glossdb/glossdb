# Interfaces

One process, one port. Each path except those marked is behind
sign-in ([deployment](../operations/deployment.md#sign-in)).

| Path | For | Writes as |
|---|---|---|
| `/mcp` | agents: the workspace | agent |
| `/<dataset>/mcp` | agents: one dataset | agent |
| `/<dataset>/query` | tools: statements in, Arrow IPC or JSON out | person |
| `/<dataset>/app` | people: the console and the data apps | person |
| `/<dataset>/app/export/<name>.csv`, `.parquet` | a table or a view as a file | |
| `/` | people: the workspace's datasets | |
| `/assets/<file>` | the console's scripts and styles; no sign-in | |
| `/auth/login`, `/auth/callback`, `/auth/logout` | the browser's sign-in; no sign-in | |
| `/.well-known/oauth-protected-resource` | the RFC 9728 discovery document; no sign-in | |
| `/healthz` | `200 ok`; no sign-in | |

A dataset the workspace does not hold is a 404 that names the ones it
does. A binding lasts one call; no path keeps a session.

## MCP

Streamable HTTP with JSON responses, without sessions. The server
serves MCP revision `2026-07-28` and negotiates down to `2025-11-25`.
The `Host` header must be a loopback host or the host of
`GLOSSDB_AUDIENCE`.

### The tool

One tool, `glossql`, with one argument, `statements`: one statement or
several separated by `;`. It takes the glossql statements and SQL.

- On `/<dataset>/mcp` each call opens on that dataset.
- On `/mcp` each call opens bound to no dataset. A call that names a
  dataset's tables begins with `USE <dataset>;`. `DECLARE DATASET`
  creates a dataset here.

The result is a JSON array with one outcome per statement:

| Statement | Outcome |
|---|---|
| a read | `{"columns": [{"name", "type"}], "rows": […], "row_count": n, "truncated": bool}`; `columns` is present with zero rows |
| a write | `{"done": "…"}` or `{"affected": n}` |
| a view definition (`GLOSS` on a `VIEW` name) | the view's row of `view_summary()` |
| a refusal | a tool error with the reason. In a sequence it names its place (`statement 2 of 7 refused: …`), and `{"completed": […]}` carries the outcomes of the statements that ran |

A data read returns at most `--row-cap` rows (default 200).
`GLOSSARY()`, `TESTS()` and the catalog tables are not capped.

### The closing lines

Each result ends with lines of context:

```
status: done — order_value: served, sliced by region
next: describe 5 · test 1 · waiting for a person 1
first: test sales.order_value (red): orphan_test: 4.6% of rows … find no parent (next://sales/test)
```

- `status:` says whether the last statement ran or was refused. For a
  view definition it adds whether the view is served and what its
  columns still need.
- `next:` counts the open rows of `next` per step. Rows that wait for
  a person are counted apart. `first:` is the first open row and the
  resource that lists its step. A read of `next` in the same call
  lists the rows counted: the built-in tests of what the call wrote
  run before its next read.
- `summary:` appears when a call changed the workspace's counts:
  decisions to apply, questions open for a person, the number of a
  person's annotations. The same call's result carries the counts as
  fields under `_meta`, key `glossdb/summary`: `line`, `datasets`,
  `assumptions_waiting`, `decisions_to_apply`,
  `load_changes_to_declare`, `annotations_by_a_person`.

### Resources and prompts

| URI | Serves |
|---|---|
| `skill://<name>/SKILL.md` | a skill: `glossql`, `glossql-modeling`, `glossql-functions`, `glossql-apps`; each is also a prompt |
| `skill://<name>/references/<page>.md` | a skill's reference pages |
| `doc://docs/<path>.md` | these docs, titled by their first heading |
| `doc://SPEC.md`, `doc://grammar.ebnf` | the language specification and grammar |
| `doc://vendor/duckdb/sql/…` | DuckDB's SQL guide for the bundled release |
| `doc://functions/interface.md` | the functions a statement can call, each once: the kits' reads and the declared functions |
| `next://<dataset>/<step>` | the open rows of one step with cause and statement; `next://<dataset>` serves each step |

The same pages are rows of `pages()` (`uri`, `title`, `body`), for a
client that reads no resources:

```sql
SELECT uri, title FROM pages();
```

### Review forms

While `open_questions` has rows, a call that only reads the catalog
(`glossary`, `GLOSSARY()`, `TESTS()`, the catalog tables) carries the
questions as MCP elicitation forms. Loads and data reads do not. The
answers arrive on the client's retry of the same call and are stored
as the person's review decisions. Anything that is not an answer
leaves the question open ([review and decide](../usage/review.md)).

## The query endpoint

`POST /<dataset>/query` with statements as the body.

- **One read** streams Arrow IPC
  (`application/vnd.apache.arrow.stream`) without a row cap. A client
  that disconnects cancels the query. A read the engine cannot start
  is a 422 with the reason.
- **Several statements, a declaration or a write** answer in the JSON
  shape of the MCP outcomes. A refused statement is a 422; a refused
  sequence carries `completed`.
- A name the catalog does not hold is a 404. A preview measurement
  whose model service is not named, refuses or does not answer is a
  503 with the reason; where none is named the reason names
  `GLOSSDB_SERVICE_URL`. The MCP tool reports the same reason as a
  refusal.

## The app paths

| Path | Serves |
|---|---|
| `/<dataset>/app` | the console |
| `/<dataset>/app/<app>` | an app's index page; `/p/<page>` a page |
| `/<dataset>/app/<app>/frames/<frame>` | a frame as Arrow IPC; URL parameters bind as `$name` |
| `/<dataset>/app/<app>/specs/<spec>` | a chart spec |
| `POST /<dataset>/app/<app>/decide` | a review decision; 409 when the question is no longer open |
| `POST /<dataset>/app/<app>/remeasure` | run stale and missing measurements again |
| `/<dataset>/app/export/<name>.csv`, `.parquet` | a table or a view as a file; another format is a 404 |

## Sign-in on the wire

A request carries `Authorization: Bearer <jwt>`, or the same token in
the `glossql_token` cookie (`HttpOnly; SameSite=Lax`) from a browser.
The MCP paths read the header only. A missing or invalid token gets a
401 with `WWW-Authenticate: Bearer resource_metadata="…"`. A browser
asking for HTML is sent to `/auth/login` (authorization code with
PKCE) and brought back. `POST /auth/logout` clears the cookie.

## Statements the server refuses

The engine's own settings are closed to actors not named in
`GLOSSDB_ROOT`: `SET`, `RESET`, `PRAGMA` switches, `ATTACH`, `DETACH`,
`INSTALL`, `LOAD`, `CALL`, `IMPORT DATABASE`, `EXPORT DATABASE`. The
refusal names the statement. Other SQL runs as DuckDB runs it.
