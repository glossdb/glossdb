# HTTP endpoints

One process, one port. Every path except those marked is behind
sign-in ([authentication](../operations/authentication.md)).

| Path | For |
|---|---|
| `/` | the workspace: its datasets, apps, interfaces and the connect line |
| `/mcp`, `/<dataset>/mcp` | agents ([MCP interface](mcp.md)) |
| `/<dataset>/query` | tools: queries in, Arrow or JSON out |
| `/<dataset>/app` | the console and the data apps |
| `/<dataset>/app/export/<name>.csv`, `.parquet` | a table or a metric as a file |
| `/assets/<file>` | the console's scripts and styles; outside sign-in |
| `/auth/login`, `/auth/callback`, `/auth/logout` | the browser's sign-in; outside sign-in |
| `/.well-known/oauth-protected-resource` | the RFC 9728 discovery document; outside sign-in |
| `/healthz` | a platform's probe: `200 ok`, outside sign-in, not logged |

The server speaks plain HTTP. A deployment terminates TLS in front of
it and sets its HTTPS URL as `GLOSSDB_AUDIENCE`.

## Dataset binding

`/<dataset>/query`, `/<dataset>/app` and `/<dataset>/mcp` carry the
dataset in the path, so a link can be shared and every call opens on
it. The binding lasts one call; no endpoint keeps a cursor. A dataset
the workspace does not hold is a 404 that lists the ones it does.

## /&lt;dataset&gt;/query

`POST /<dataset>/query` with statements as the body.

- **A single read** streams Arrow IPC
  (`application/vnd.apache.arrow.stream`) as the engine produces it: no
  row cap, memory bounded by one batch, and a client that disconnects
  cancels the query. The status is set on the first batch: a read the
  engine cannot start is a 422 with the reason. An error after data
  has flowed ends the body without its final chunk, so the client sees
  a truncated stream; the server logs the reason. pyarrow reads the
  stream directly.
- **Anything else** — several statements, declarations, writes —
  answers in the JSON shape of the [MCP results](mcp.md#results). A
  refused statement is a 422 with the reason; a refused sequence
  carries the outcomes of the statements that ran under `completed`.

The query endpoint writes as a person.

## /&lt;dataset&gt;/app

The console and the data apps ([app authoring](apps.md)):

| Path | Serves |
|---|---|
| `/<dataset>/app` | opens the console |
| `/<dataset>/app/{app}` | an app's index page |
| `/<dataset>/app/{app}/p/{page}` | a page |
| `/<dataset>/app/{app}/frames/{frame}` | a frame as Arrow IPC; URL parameters bind as `$name` |
| `/<dataset>/app/{app}/specs/{spec}` | a chart spec |
| `POST /<dataset>/app/{app}/rule` | a review decision |
| `POST /<dataset>/app/{app}/remeasure` | run stale and missing measurements again |

Frames only read; they run as the person `app:<name>`. The two writes
are a person's, as the token's subject. A review decision is accepted
only while `open_questions` still has that exact (subject, aspect, key)
in the bound dataset: a stale tab gets a 409, and the stored text comes
from the server's own row, never from the browser. Success is a 204
with `HX-Trigger: glossql:written`.

### Export

`GET /<dataset>/app/export/<name>.csv` or `.parquet`, where `<name>` is
a table or a metric, streams it as it is at the read, the same way a
frame does. Parquet keeps the engine's types; CSV is text. A name the
dataset does not hold is the engine's refusal (422) with its text; any
other format is a 404. A filter or a query of your own goes to
`/<dataset>/query`.

## Sign-in

Every request carries a bearer token: `Authorization: Bearer <jwt>`
from a machine, or the same token in a `glossql_token` cookie
(`HttpOnly; SameSite=Lax`) from a browser on `/`, `/query` and `/app`.
The MCP paths read the header only. A missing or invalid token gets a
401 with `WWW-Authenticate: Bearer resource_metadata="…"`, pointing at
the discovery document, which names the `resource` (the audience) and
the `authorization_servers` (the issuer). A browser asking for HTML is
sent to `/auth/login` instead and brought back afterwards.

Every request is checked for its signature (by the key the token's
`kid` names, with the algorithm that key allows), `iss`, `exp`, and an
`aud` naming `GLOSSDB_AUDIENCE`. The issuer's key set is fetched at
start and again only when a token names a key not in it; a server that
cannot reach its issuer does not start. A refusal is logged with its
reason, never with the token.

The browser's sign-in is authorization code with PKCE (RFC 7636), the
resource named per RFC 8707. `/auth/callback` exchanges the code at the
issuer as the registered application, verifies the token like every
other request, and sets the cookie. The sign-in in progress (state,
PKCE verifier, where to return) is a ten-minute cookie scoped to
`/auth`; the server keeps no session. The return address is a path on
this server and nothing else: one that reads as another host, or has a
backslash or a control character, goes to `/`. `POST /auth/logout`
clears the cookie; a GET does not, since any page could link to it.

Pages are served under a `Content-Security-Policy` that runs the
server's own assets only, so a page an agent wrote cannot act with the
viewer's sign-in ([app authoring](apps.md#pages)).

Details of the token checks and the issuer setup:
[authentication](../operations/authentication.md).
