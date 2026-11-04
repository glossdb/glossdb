# The lineage plan

The evaluation behind one addition to SPEC.md §3 and §5.2: a landing
records what computed each of its columns, and `stale` reads
re-derivation from that record. The extension runs this form
(`../gloss/src/glossql_lineage.cpp`), serves it as `glossql_lineage(sql)`
and lands it on every import; its suite holds the cases. The SPEC
wording is a proposal: the language has one owner.

## The table

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| One derivation vocabulary: a leaf is `scan.column:type`, an expression is its function's or operator's name over its children's texts, no alias, no binding, nothing of the plan's shape; a column the walk cannot follow carries a digest of the recipe | Built: the extension walks the bound plan before any optimizer runs | `../gloss/src/glossql_lineage.cpp`, its suite | | language, not an issue |
| SPEC §3 and §5.2 say it: a landing records each column's derivation, and a gloss reads `stale` once the derivation behind its column moved, a source sending a column under another type included | Low | `SPEC.md` §3 re-land paragraph, §5.2 `snapshot_id` bullet | The lead's verdict | language, not an issue |
| The concept page says what a landing records and how `stale` reads it | Low | `docs/concepts/imports.md` | With the SPEC row | |
| A measurement's lineage: the same walk over its body names the columns it read, finer than the tables `reads` names | Medium | the extension's `ReadsOf` | Later | |

## What stands

- SPEC §3: a changed recipe re-lands, and a gloss on a column the
  re-land re-derived, retyped or dropped reads `stale`. §5.2: every
  gloss carries `snapshot_id`, and staleness is a join against the
  catalog's column history, never a guess.
- The extension walks the bound plan bottom up, a text per column
  binding: a scan's column is `scan.column:type`; a projection,
  aggregate, window or unnest writes its expressions' texts; a set
  operation joins its sides' texts; a CTE is walked definition first;
  filters, orders, limits and joins pass bindings through. Each landing
  lands the map on its imports row. The stale rule compares the landing
  that stood at the gloss's snapshot with the newest, per column; a
  table is stale once any key moved; a column added or a filter changed
  ages nothing. The suite holds a recipe that re-derives one column, and
  a source under `SELECT *` whose column arrives as a double where it
  was an integer while the landed column keeps its type.
- The metrics kit's `metric_sources(metric)` reads a metric's sources
  through `glossql_lineage`.

## The reasoning

- **The leaf carries the source's type** because that is where drift
  the catalog cannot see lives: under a cast, or under a recipe that
  lands the source's type as it comes, the landed column keeps its type
  while the source changed its mind. The column history says current;
  the lineage says moved.
- **Per landing, not per declaration.** A declaration fixes the SQL; a
  landing is the SQL meeting the source as it stands. The landings'
  diff is a drift record of what a source sends, readable with plain
  SQL.
- **Through joins and unions**, because a recipe over two tables is the
  common case and a column from a join is derived from something; a
  text that stops at the root cannot say what.
- **Text, no structure.** The rule is two texts equal or not. A graph a
  reader walks is a later reader's business.
- **One vocabulary across pins, reads and lineage.** A pin names
  `dataset.table:version`, reads name `dataset.table`, a lineage leaf
  names `dataset.table.column:type`. A measurement's lineage is the
  same walk over its body, the last row of the table.

## The SPEC diff, proposed

- §3, the re-land paragraph: "a gloss on a column the re-land
  re-derived, retyped or dropped reads as `stale`" holds, with one
  sentence after it: "Every landing records what computed each column,
  resolved to the source's columns and their types; a column is
  re-derived once that record moved, which a changed recipe does and so
  does a source that sends a column under another type."
- §5.2, the `snapshot_id` bullet: "a column re-derived, retyped or
  dropped" holds; "Provenance and staleness are a join against the
  catalog's column history, never a guess" becomes "Provenance and
  staleness are a join against the catalog's column history and the
  landings' lineage, never a guess."
