# The lineage plan

Column lineage is built in the extension: every load records what
computed each of its columns (`glossql_lineage(sql)`), a view's
columns say which loaded columns they descend from
(`glossql_views_lineage(dataset)`), and a view names every table it
scans (`glossql_views_scans(dataset)`). An annotation on a column the
re-load re-derived, retyped or dropped reads `stale` (SPEC §3, §5.2).
The extension's docs say it (`docs/usage/lineage.md`). The server
reads it for `metric_sources()`, the console's lineage page and the
built-in tests on metrics. What is left is one SPEC sentence, finer
reads for measurements, and the industry's export format.

## The table

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| SPEC §3 says in one sentence what a load records: each column's derivation resolved to the source's columns and types, so a changed load query and a source that sends a column under another type both re-derive it | Low | `SPEC.md` §3 | the lead's verdict | language, not an issue |
| A measurement's reads at column level: the walk over its body names the columns it read, finer than the tables and the per-function measurement rows `reads` names today | Medium | the extension's `ReadsOf` | when a check needs it | |
| Lineage exported as OpenLineage events, so a catalog a customer already runs reads glossdb's loads and views | Low | the server, an export endpoint | when a customer names the catalog | |

## What stands

- A derivation is text: a leaf is `scan.column:type`, an expression is
  its function's or operator's name over its children, through joins,
  unions and CTEs; a column the walk cannot follow carries a digest of
  the load query. Equal texts mean nothing moved.
- Per load, not per declaration: the loads' derivations over time are
  the drift record of what a source sends, including a type that
  changed under a cast.
- A measurement's `reads` names the tables and store relations its body
  scanned, and since glossql #25 the other functions' measurements it
  filtered to; `**` when a scan could not be enumerated.

## The SPEC sentence, proposed

§3, after "a gloss on a column the re-land re-derived, retyped or
dropped reads as `stale`": "Every load records what computed each
column, resolved to the source's columns and their types; a column is
re-derived once that record moved, which a changed load query does and
so does a source that sends a column under another type."
