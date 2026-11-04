# The gate plan

The door's gate stands in the facade (`crates/duck/src/lib.rs`,
`admitted`): a standard actor's statement is judged by its first
words before it runs, and `GLOSSDB_ROOT` names the actors who have
the engine's knobs. This file plans the gate's move into the engine,
where the engine's own parse judges, and the two angles beyond
statement kinds: what data an actor may touch, and the standard the
model follows.

The rules: policy stays in this repository (who is root, later who
holds which grant); the mechanism is the engine's; the extension
carries no concept of the server; `docs/concepts/statements.md`
states what the door closes.

## The table

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The latch: a connection closed to the engine's own statements, judged at the prepare hook by the engine's statement kind | Low. The seams are measured below; one wrinkle, the extension's own statements on the same connection | Extension: a `ClientContextState` per connection, a one-way switch, its tests. Facade: `channel()` switches a standard actor's connection after its own `SET`s; `admitted`, `words`, `Session::admit` and the pragma guess go; the duck and doors suites. Docs: statements.md, sql-here.md, install.md | Next, after the open pull requests merge | drafted below |
| Data access: what a statement reads and writes, per actor, judged on the plan | Medium. The seam is unmeasured; a grounding is a view, so a read of a metric plans its base tables; the store's relations are read by all and written by the language | Extension: the plan walk at the optimizer hook or the prepare hook, the refusal's text. Facade: who holds which grant | When a workspace has a second user | |
| Roles and grants in the record | High. Vocabulary is grammar, and a form goes through the corpus | SPEC and corpus (the extension); the store; the door's config | After data access measures a need | |

## What stands, measured

- DuckDB has no users, no grants and no per-connection filter. Its
  security settings are instance-wide and lock root out as well; none
  freezes a session variable.
- The hook: `ClientContextState::OnFinalizePrepare` runs for every
  statement after planning (`duckdb/src/main/client_context.cpp:389`)
  with `PreparedStatementData::statement_type`, after the preprocessor
  rewrote pragmas (`PRAGMA table_info` is a `SELECT` by then, `PRAGMA
  enable_profiling` a `SET`; `src/planner/statement_preprocessor.cpp`).
  `INSTALL`, `LOAD` and `FORCE INSTALL` are one kind, `LOAD`.
- The optimizer hook sees every plan but `PREPARE`'s
  (`src/planner/planner.cpp:62`), so the data angle can walk
  `LogicalGet`, `LogicalInsert`, `LogicalUpdate`, `LogicalDelete` and
  the create operators with their catalog entries. The operator
  extension's bind runs only after the regular bind failed
  (`planner.cpp:219`).
- The extension's `Inner` runs on the caller's connection
  (`src/include/glossql_grammar.hpp:172`): the runner's `SET
  search_path` and `SET file_search_path` during `IMPORT` would meet
  the latch, so the exemption rides `Inner`.
- Quack, 2.0's server mode, offers `quack_authorization_function
  (connection_id, query)` for its wire alone; the doors embed the
  engine.
- The Rust crate keeps `duckdb_prepared_statement_type` and the raw
  connection private; the kind is reachable from the extension only.
- The kinds closed to a standard actor: `SET` (settings, variables,
  `RESET`), `ATTACH`, `DETACH`, `LOAD`, `UPDATE_EXTENSIONS`, `CALL`,
  `EXPORT`, `COPY_DATABASE`, `PREPARE`, `EXECUTE`, `CONNECT`,
  `DISCONNECT`, `EXTERNAL_RESOURCE`. Open: `SELECT`, `INSERT`,
  `UPDATE`, `DELETE`, `MERGE_INTO`, `CREATE`, `CREATE_FUNC`, `ALTER`,
  `DROP`, `COPY`, `TRANSACTION`, `EXPLAIN`, `ANALYZE`, `VACUUM`, and
  `EXTENSION`, the language's statements.

## The standard

- The model is core RBAC as ANSI INCITS 359 defines it: users, roles,
  permissions, and sessions in which a user's roles are active. An
  actor is the user; root and standard are the roles today; a channel
  is the session, its roles fixed at open, which the latch makes
  literal.
- The words for data access are the SQL standard's (ISO/IEC 9075-2,
  access control): `SELECT`, `INSERT`, `UPDATE`, `DELETE` on a table,
  `USAGE` on a schema, `EXECUTE` on a routine, granted to a role and
  revoked by name. A dataset is a schema, a metric a view, the store's
  relations the record's.
- What the standard has no word for stays named plainly: the engine's
  own statements (the first row) and the language's statements, open
  to every role.

## The next row's issue, drafted

**The gate moves into the engine: a connection latched against the
engine's own statements**

What it buys: the door's gate judged by the engine's parse, after its
pragma rewrite, on every path through a connection; the facade's word
scanner and its three call sites go.

What stands: `crates/duck/src/lib.rs` (`admitted`, `words`,
`after_comments`, `Session::admit`, `Plane::channel`); the duck
suite's `the_door_opens_the_workspace_and_closes_the_engine`; the
doors suite's `the_query_door_closes_the_engine_to_a_standard_actor`;
`docs/concepts/statements.md`, "What the door closes".

Done when: the extension registers a per-connection state that, once
switched, refuses the closed kinds at `OnFinalizePrepare` with a
message naming the kind, cannot be switched back on that connection,
and exempts its own `Inner`; `channel()` switches it for a standard
actor after its own `SET`s; the facade's scanner is deleted; both
suites hold their assertions against the engine's refusals; the docs
name the kinds.
