# What will bite — read on the first refusal, or before a complex read

The engine is DuckDB at a pinned release, and its own SQL guide for
that release is served here as `doc://vendor/duckdb/sql/…` — the
query syntax, the expressions, the functions by family, the data
types. A function's name, signature or absence is a lookup there,
not a guess. This page is what the guide cannot say.

The MCP interface opens the workspace: tables, rows, files, views,
the language, the reads. Closed is the engine: `SET` (the actor comes with the
connection), `ATTACH`, `INSTALL`, `LOAD`, `CALL`. A named argument to the server's
own table macros spells `:=` (`metric_series(grain := 'month')`); the
engine's functions take their own arguments as the guide spells them.

Names are case-insensitive, quoted or not: `AdsInfo`, `adsinfo` and
`"AdsInfo"` reach the same table, and a column loaded with capitals
from a source header keeps that spelling in every listing and is
reached by it in any case. A name that is a reserved word is quoted:
`"at"`, `"order"`.

The schema in one read: `information_schema.tables` and
`information_schema.columns` serve the bound dataset's tables and
every column of them; `SHOW TABLES` lists the loaded tables and the
metric definitions' views; `DESCRIBE <name>` describes any readable name, the
shipped reads included — `DESCRIBE band_points()`.

What goes wrong without failing: an inner `ORDER BY` does not
survive a derived relation, so order where you consume · `lag` and
ROWS frames count rows, not periods, so densify before you lag ·
`GROUP BY ALL` re-groups when someone edits the select list, so a
stored metric definition spells its GROUP BY · `try_cast` is the only safe
cast on dirty text; `CAST` refuses the row.

A column loaded as text: `max`/`min` are lexicographic (`'99' >
'100'`) and `sum` refuses the type. The cast belongs in the load query;
`try_cast` at the read is the stopgap.

A measurement is called in the SELECT list with its subject in FROM —
`SELECT column_profile() FROM orders.amount` — never as a table
function; `SELECT * FROM column_profile()` is refused.
