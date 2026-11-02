# DuckDB's SQL guide at the pin

These pages are the SQL guide of DuckDB, verbatim, for the release in
`VERSION` at the duckdb-web commit named there. That is the engine
behind every read on the door. The door serves them as
`doc://vendor/duckdb/sql/<section>/<page>.md`: the query syntax, the
expressions, the functions, the data types and the SELECT statement's
own page. MIT license, `LICENSE` kept.

What differs here, which the guide cannot say:

- The door serves reads. DDL, DML, COPY and the statements that move
  the catalog are closed; tables come from recipes. Those pages are
  not vendored.
- A named argument to the door's own table functions spells `:=`
  (`metric_series(grain := 'month')`).

`skill://glossql/references/sql-here.md` keeps the rest: what the door
serves of the engine, and what it does not.

Refresh at every pin move: `vendor/duckdb/refresh.sh <docs version>
<duckdb-web commit>`. The serverd suite refuses a VERSION that is not
the lock's.
