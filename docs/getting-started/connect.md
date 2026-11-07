# Connect

Agents connect over MCP, people over the browser, and tools over HTTP.
One server, one port:

| Path | For | Serves |
|---|---|---|
| `/<dataset>/mcp` | agents | one dataset: every call opens on it |
| `/mcp` | agents | the whole workspace: declare sources and create datasets; `USE` picks the dataset per call |
| `/<dataset>/query` | tools | a query in, an Arrow stream out ([querying](../usage/querying.md)) |
| `/<dataset>/app` | people | the console ([the console](../usage/console.md)) |
| `/` | people | the workspace: its datasets and the way into each |

Every request carries a bearer token from the workspace's identity
provider; the token's subject is the actor. The MCP paths write as an
agent, the others as a person ([authentication](../operations/authentication.md)).

## Claude Code

```bash
set -a; source .env; set +a      # the same application the server is registered as
MCP_CLIENT_SECRET=$GLOSSDB_CLIENT_SECRET claude mcp add --transport http \
  --client-id $GLOSSDB_CLIENT_ID --client-secret --callback-port 3118 \
  glossdb http://127.0.0.1:8080/fin/mcp
claude mcp login glossdb
```

The callback port is the loopback redirect the provider's application
must list (`http://localhost:3118/callback`); any port but the
server's own. `login` opens the provider's sign-in in a browser and
stores the token; Claude Code refreshes it on its own.

Add one entry per dataset the agent works on, or one entry at `/mcp`
for the whole workspace, where the agent picks its dataset with `USE`.

With sign-in off (`GLOSSDB_INSECURE_OPEN=true`) no token is needed:

```bash
claude mcp add --transport http glossdb http://127.0.0.1:8080/mcp
```

## Other MCP clients

Any client that speaks streamable-HTTP MCP at revision `2026-07-28`
and OAuth works. A call without a token gets a 401 with the discovery
pointer an OAuth-capable client follows.

## The MCP interface

The interface is stateless: no sessions. It has one tool, `glossql`.
Its `statements` argument takes a statement or a semicolon-separated
sequence; the result is a JSON array, one outcome per statement:

- **a read**: `{"columns": [...], "rows": [...], "row_count": n,
  "truncated": bool}`. `columns` carries the result's shape with
  DuckDB's types even at zero rows, so a `LIMIT 0` query returns the
  schema. Data rows stop at `--row-cap`; `truncated: true` means refine
  the query, not that the result is complete. Catalog reads,
  `GLOSSARY()`, `TESTS()` and the catalog tables, arrive whole.
- **a write**: `{"affected": n}` or `{"done": true}`.
- **a refusal**: a tool error whose text names what was wrong and, in a
  sequence, its place. The statements before it ran; the rest did not.

**On a dataset's path,** every call opens on that dataset. Its tables
and columns resolve unprefixed, another dataset's with the dataset's
name in front, and the result ends with the dataset's `next:` line. A
dataset the workspace does not hold is a 404 naming the ones it does.

**On the workspace path,** begin a call with `USE <dataset>;` to work
on a dataset. MCP has no session to hold a binding, so the statements
carry it: `USE` applies to the statements after it and ends with the
call. A call that names no dataset works on the workspace, which is
what `SELECT * FROM datasets` and a source's annotation want. A dataset
the workspace does not hold yet is not an error here: `DECLARE DATASET`
creates it.

**Review questions arrive as forms.** While questions are open, a call
that reads the catalog carries them as MCP elicitation forms. The
answers arrive on the client's retry of the same call and are stored as
the person's annotations. Anything that is not an answer defers: the
question stays open and is asked again ([the review queue](../usage/review.md)).

The skills that teach an agent the language and the work ship with the
server: `glossql`, `glossql-metrics`, `glossql-functions` and
`glossql-apps`, served as MCP resources and prompts. Every interface
detail: [the MCP interface](../reference/mcp.md).

## A browser

Open `http://127.0.0.1:8080/`: the workspace, with every dataset and
the way into each. The server sends the browser to the identity
provider to sign in, then back with the token in a cookie
(`/auth/login`, `/auth/callback`; a POST to `/auth/logout` clears it).
The person signing in is the token's subject: the same name an agent's
connection carries when that person is behind it.
