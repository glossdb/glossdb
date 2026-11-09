# Access control plan

Today the server checks each statement of a non-admin user by its
first words before it runs (`admitted` in `crates/duck/src/lib.rs`).
`GLOSSDB_ROOT` names the admins, who may run any DuckDB statement.
This plan moves the check into the engine, where DuckDB's own parser
decides the statement type, and then adds access per table.

Who is admin, and later who holds which grant, stays this
repository's. The mechanism is the extension's, and the extension
knows nothing of the server. `docs/reference/statements.md` says what
is refused.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Statement-type lock: a connection that refuses DuckDB's own administrative statements, checked after planning by statement type | Low. The hooks are measured below. One wrinkle: the extension runs its own statements on the same connection | Extension: a per-connection state with a one-way switch, its tests. Server: `channel()` switches it for a non-admin after its own `SET`s; `admitted`, `words`, `after_comments` and `Session::admit` are deleted; both suites. Docs: statements.md, sql-here.md, installation | Next | drafted below |
| Table access: what a statement reads and writes, per user, checked on the query plan | Medium. The hook is unmeasured. A metric is a view, so reading it plans its base tables. The catalog tables are read by everyone and written only through glossql statements | Extension: a walk over the plan, the refusal text. Server: who holds which grant | When a workspace has a second user | |
| Roles and grants stored in the catalog | High. `GRANT` is grammar, so it goes through the corpus | SPEC and corpus (extension); the catalog; the server's config | After table access shows the need | |

## Measured

- DuckDB has no users, no grants and no per-connection filter. Its
  security settings apply to the whole instance and lock the admin
  out too. None freezes a session variable.
- `ClientContextState::OnFinalizePrepare` runs for every statement
  after planning (`duckdb/src/main/client_context.cpp`) with the
  statement type, after pragmas are rewritten: `PRAGMA table_info` is
  a `SELECT` by then, `PRAGMA enable_profiling` a `SET`. `INSTALL`,
  `LOAD` and `FORCE INSTALL` are one type, `LOAD`.
- The optimizer hook sees every plan except `PREPARE`'s, so table
  access can walk `LogicalGet`, `LogicalInsert`, `LogicalUpdate`,
  `LogicalDelete` and the create operators with their catalog entries.
- The extension runs its inner statements on the caller's connection
  (`Inner`, `src/include/glossql_grammar.hpp`). `IMPORT` runs `SET
  search_path` and `SET file_search_path`, so `Inner` is exempt from
  the lock.
- DuckDB's server mode has an authorization callback for its own wire
  protocol only. glossdb embeds the engine, so it does not apply.
- The Rust crate keeps the statement type and the raw connection
  private. Only the extension can read the type.
- Refused for a non-admin: `SET` (settings, variables, `RESET`),
  `ATTACH`, `DETACH`, `LOAD`, `UPDATE_EXTENSIONS`, `CALL`, `EXPORT`,
  `COPY_DATABASE`, `PREPARE`, `EXECUTE`, `CONNECT`, `DISCONNECT`,
  `EXTERNAL_RESOURCE`.
- Allowed: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `MERGE_INTO`,
  `CREATE`, `CREATE_FUNC`, `ALTER`, `DROP`, `COPY`, `TRANSACTION`,
  `EXPLAIN`, `ANALYZE`, `VACUUM`, and `EXTENSION` (the glossql
  statements).

## The standard we follow

- Role-based access control as in ANSI INCITS 359: users, roles,
  permissions, and sessions with a fixed set of active roles. Today
  the roles are admin and standard; a connection is the session.
- Table access uses the SQL standard's words (ISO/IEC 9075-2):
  `SELECT`, `INSERT`, `UPDATE`, `DELETE` on a table, `USAGE` on a
  schema, `EXECUTE` on a routine, granted to a role and revoked by
  name. A dataset is a schema; a metric is a view.
- The glossql statements are open to every role.

## Issue for the next row, drafted

**A connection locked against DuckDB's administrative statements**

What it buys: the statement check uses the engine's parse, after its
pragma rewrite, on every path through a connection. The server's
word scanner and its three call sites are deleted.

What is there: `crates/duck/src/lib.rs` (`admitted`, `words`,
`after_comments`, `Session::admit`, `Plane::channel`); the two suite
cases that assert the refusals; `docs/reference/statements.md`.

Done when: the extension registers a per-connection state that, once
switched, refuses the listed types at `OnFinalizePrepare` with a
message naming the type, cannot be switched back, and exempts its own
`Inner`. `channel()` switches it for a non-admin after its own
`SET`s. The server's scanner is deleted. Both suites assert the
engine's refusals. The docs list the types.
