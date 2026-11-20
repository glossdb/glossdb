# Access control plan

Today the server checks each statement of a non-admin user by its
first words before it runs (`admitted` in `crates/duck/src/lib.rs`).
`GLOSSDB_ROOT` names the admins, who may run any DuckDB statement.
This plan moves the check into the engine, where DuckDB's own parser
decides the statement type, and then adds access per table.

Who is admin, and later who holds which grant, stays this
repository's. The mechanism is the extension's, and the extension
knows nothing of the server. `docs/reference/interfaces.md` says what
is refused.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Statement-type lock: a connection that refuses DuckDB's own administrative statements, checked after planning by statement type | Low. The hooks are measured below. One wrinkle: the extension runs its own statements on a second connection it opens per statement | Extension: a per-connection state with a one-way switch, its tests. Server: `channel()` switches it for a non-admin after its own `SET`s; `admitted`, `words`, `after_comments` and `Session::admit` are deleted; both suites. Docs: `docs/reference/interfaces.md` | Next | #254 |
| A source's reads are confined to its declared location. Today a load query can read outside it, for example `read_parquet('../other/file.parquet')` | Medium. DuckDB's file settings apply to the whole instance, so the check is per load: on the plan of the load query, or on the paths it opens | Extension: the load (`IMPORT`, `DECLARE RECIPE`, `PREVIEW`), the refusal text, its tests. Server: both suites; `docs/usage/load.md` and `docs/reference/interfaces.md` say what is refused | With table access | |
| Table access: what a statement reads and writes, per user, checked on the query plan | Medium. The hook is unmeasured. A metric is a view, so reading it plans its base tables. The catalog tables are read by everyone and written only through glossql statements | Extension: a walk over the plan, the refusal text. Server: who holds which grant | When a workspace has a second user | |
| A log of the statements an agent or a person ran, if it is built (`harness.md`): who reads it. A statement can hold values of the data in its literals, and a kept query can hold the value it returned, so a read of the log follows the access to the tables the statement read | Medium. Decided with the design of the log, not after it | Server: the log's read; the extension if the log is a catalog relation | With table access, or with the log if that comes first | |
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
- The extension runs its inner statements on a second connection it
  opens per statement (`Inner`, `src/include/glossql_grammar.hpp`).
  `IMPORT` runs `SET search_path` and `SET file_search_path` there.
  Whether the lock has to exempt that connection is measured again
  with the first row.
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

## Next issue

#254: a connection locked against DuckDB's administrative statements.
