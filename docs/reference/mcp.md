# MCP interface

Agents connect over the Model Context Protocol. The server is one
service at two paths: `/mcp` for the whole workspace, `/<dataset>/mcp`
for one dataset. How to connect a client:
[connect](../getting-started/connect.md). The other endpoints:
[HTTP endpoints](http.md).

## Transport

Streamable HTTP with JSON responses, served without sessions: no
`Mcp-Session-Id`, no GET stream, no resumability. The server speaks
protocol revision `2026-07-28` and negotiates down to `2025-11-25` for
older clients. A request with no version header is served at the
server's own revision, which is what the specification has a server
assume. A client below the oldest revision is refused with the
revisions the server speaks.

The `Host` header must be a loopback host or the host of
`GLOSSDB_AUDIENCE`, the server's own URL. A deployment that does not
set it answers only its bind address.

## Binding a dataset

`/<dataset>/mcp` opens every call on that dataset. `/mcp` opens every
call bound to no dataset: a call that names a dataset's tables or
columns begins with `USE <dataset>;`. MCP keeps no session, so the
binding lasts one call, and `USE` (or the URL) is how each call says
where it works. A call that names no dataset works on the workspace:
listing `datasets`, declaring a source. `DECLARE DATASET` creates a new
dataset, so `/mcp` is where datasets begin. Full
`dataset.table.column` names resolve from any binding.

## The tool

One tool, `glossql`, with one argument, `statements`: one statement or
several separated by `;`. It takes the glossql statements and plain
SQL ([statements](statements.md)). Its description is the contract for
every call: how a call is bound, the result shapes, the refusal shape
and the review queue. A client carries the tool list on every turn and
fetches a resource once, if at all, so the description is where the
rules live.

### Results

The result is a JSON array, one outcome per statement:

- **A read:** `{"columns": [{"name", "type"}, …], "rows": […],
  "row_count": n, "truncated": bool}`. `columns` is present even with
  no rows, so `LIMIT 0` returns the schema.
- **A write:** `{"done": "…"}` or `{"affected": n}`.
- **An annotation of a metric definition** (`GLOSS` on a `VIEW`
  aspect): the metric's summary row in the `metric_axes()` shape, at
  the catalog version the write created: whether the SQL plans, its
  additivity and where that came from, the slicing columns admitted,
  and each served column not admitted with how to admit it
  ([views and table functions](reads.md)).
- **A refusal:** a tool error whose text is the refusal. In a sequence
  it names its place, `statement 2 of 7 refused: … — statement 1 ran;
  3–7 not run`, and a second block carries the outcomes of the
  statements that ran (`{"landed": […]}`). What ran stays; what came
  after was not attempted.

### Row cap

A data read returns at most `--row-cap` rows (default 200) and sets
`truncated`. The cap is part of the read's plan, so the engine stops
early and a sort keeps only the capped rows. Catalog reads —
`GLOSSARY()`, `TESTS()` and the catalog tables — are never capped.

### The two closing lines

Every result ends with two lines:

- `situation:` says whether the last statement ran (`situation: done`)
  or was refused, with the refusal's first line. For a metric
  definition it adds the summary row: the slicing columns admitted, the
  columns not admitted, the measurements wanted.
- `next:` names one action per goal — `structure`, `metrics`,
  `slices`, `bands`, `checks`, `app`, `plan`, `rulings` — each with a
  link, `next://<dataset>/<goal>`. A blocked goal says what blocks it;
  a finished one says `done`. The goal is the caller's choice, never
  stored. How the goals work: [next steps](../extending/next-steps.md).

### The brief

The initialize instructions end with one line over live counts, and the
same line comes back on any tool result whose call changed them. First
what waits: review decisions not yet applied, approved load-query
changes not yet declared again, questions open for a person. Then the
catalog's size: how many annotations people wrote, and the latest. The
instructions then say where to begin: a workspace with no dataset reads
`workspace_next`; one with a dataset starts with the brief, once, as a
read and never a gate.

## Resources and prompts

The server serves the pages an agent learns from:

| URI | What |
|---|---|
| `skill://<name>/SKILL.md` | each skill; also a prompt of the same name |
| `skill://<name>/references/<page>.md` | a skill's reference pages, listed by their title line |
| `doc://docs/<section>/<page>.md` | these docs |
| `doc://SPEC.md`, `doc://grammar.ebnf` | the language specification and grammar |
| `doc://vendor/duckdb/sql/…` | DuckDB's SQL guide for the bundled release |
| `doc://functions/door.md`, `doc://functions/recipe.md`, `doc://functions/detector.md` | every function each execution context has, read when the server opened |
| `next://<dataset>/<goal>` | a template: where one goal stands and the statement that moves it |

The same pages are the rows of `pages()`, so a client without a
resource reader reads them through the tool. Everything is embedded at
build time, so what a build serves is what its tests checked.

## The review queue

While `open_questions` has rows, a call that only reads the catalog
(`glossary`, `GLOSSARY()`, `TESTS()`, the catalog tables) carries
the questions as forms; loads and data reads never do. Each question is
one form with these choices:

- **Correct as stated.**
- **Rather, this reading:** the alternative the agent named.
- **Same as before:** where the person already decided the same key
  under another aspect.
- **The question itself is unclear:** the question, not the claim, is
  refused; it will be asked differently.
- **What is right instead:** free text that outranks every choice
  above.

The answers arrive on the client's retry of the same call and are
stored as the person's annotations under the same subject, recorded as
seen by the server. Anything that is not an answer defers: the question
stays open and is asked again on the next catalog read. Where the
client cannot show forms, the agent relays the question in chat. How
the queue works: [the review queue](../usage/review.md).

## Who is speaking

The token's subject is the actor ([authentication](../operations/authentication.md)).
Both MCP paths write as an agent. Without a token, under
`GLOSSDB_INSECURE_OPEN`, a call writes as `insecure_dev_mode` with an
agent's standing. The client's own `clientInfo` name is not used: a
caller can send any name, so it proves nothing.
