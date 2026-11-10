# Sources plan

What can be loaded beyond CSV, Parquet and JSON: spreadsheets,
documents, databases, and search over text. A source is what a load
query (`DECLARE RECIPE`) reads: files through DuckDB's readers, a
database DuckDB attaches, or a service called through the extension's
`glossql_service` (one table in, one table out). Importing a dbt
project or an Ossie semantic model, and reading a lake in place, are
issue #221.

| Element | Difficulty | What it touches | When | Issue |
|---|---|---|---|---|
| Spreadsheets: the values through DuckDB's `excel` extension; formulas, defined names and macro modules as rows through a separate reader | Easy for values; formulas need the reader | SPEC §3, `reader_functions()` in `crates/duck`, the image's extensions | First | |
| Documents: a processing service the load query calls, text as passages | Easy | SPEC §3, one service through `glossql_service` | After spreadsheets | |
| Search: `embed(text)` as a scalar service call, distance with DuckDB's `array_distance` | Easy | the extension's service call, one service | After documents | |
| Databases: one DuckDB attaches (`postgres`, `sqlite`, `mysql`) or an Iceberg catalog, read-only, read by a load query | Low: the extensions exist and the image carries `postgres` | SPEC §3's `via`, the server's open, a suite case | When a customer names one | |
| Vector index | Medium | DuckDB's `vss` extension | When the full scan is too slow | |
| Ranking experiment | Easy, outside this repository | glossval | Beside the rest; blocks nothing | |

## What is there

- SPEC.md §3 names the source types: `relational_db | parquet | csv |
  json`. `grammar.ebnf` lists the same keys in a comment, so a new
  type is a spec change. A load query is DuckDB SQL over `read_csv`,
  `read_parquet` and `read_json` (`reader_functions()` in
  `crates/duck/src/lib.rs`) and loads one table with the types the
  query casts.
- `glossql_service` calls a service from SQL with one table in and one
  out. The URL and bearer token are set once per instance. The
  forecast and the scenario estimate use it. The scalar form, one text
  in and one vector out, is new with `embed`.
- Search ranks rows for a reader. A similarity is never a join key,
  never an identity, and never closes a question. Identity is an
  explicit key.

## Issues, drafted

When one is opened, its number goes into the table and the draft
leaves this file.

### Spreadsheets as a source

- **What it buys.** A company's workbook is loaded as tables, and its
  formulas, defined names, macro modules and queries as rows. An
  agent reads a formula and writes the metric definition; the
  assumption's basis names workbook, sheet and cell. A migration is
  checked against the values the workbook stored. A budget is loaded
  as a plan's table. No calculation engine.
- **What is there.** SPEC.md §3 names four types. DuckDB's `excel`
  extension reads a sheet's values. A Rust reader for formulas, macro
  source, defined names and tables in xlsx, xlsm, xlsb, xls and ods
  exists (calamine). Neither reads pivot tables or Power Query.
- **Done when.** The corpus holds one real workbook and SPEC.md §3
  names the type. A fixture workbook loads as tables and as
  definition rows keyed by path, sheet, and cell or name. A metric
  definition's basis names a cell, and its result equals the
  workbook's stored value. The suite asserts it.

### Documents as a source

- **What it buys.** A handbook, a standard or a schema description is
  loaded as passages. An agent finds the passage, writes a convention
  or a definition, and cites the passage by key.
- **What is there.** SPEC.md §3, the load query, `glossql_service`. An
  open-source server that reads PDF, Word and slides into structure,
  tables and reading order exists (docling). It runs per deployment,
  since the text is customer content.
- **Done when.** The corpus holds one real handbook and SPEC.md §3
  names the type. A fixture document loads as passage rows: document,
  reference, ordinal, headings, kind, text, page; the key is document
  and reference. Processing the same document again with one
  paragraph added keeps the other passages' references, or the issue
  records that we need a key of our own. An annotation cites a
  passage by key, and the suite asserts it.

### Search: embed as a scalar service call

- **What it buys.** An agent finds a passage by meaning, not by
  string.
- **What is there.** `array_distance` is DuckDB's. The service call's
  table form exists in the extension; the scalar form is this issue.
- **Done when.** `embed(text)` is a scalar function a load query can
  call. An embedding service the deployment names answers it; without
  one, the call is refused by name. The load query stores the vector
  at unit length and the column records the model's name and
  revision. A query ordered by `array_distance` over a full scan
  returns the fixture passage in the top rows. 10,000 passages load
  with the service stopped half-way and no half table results. The
  time per passage is recorded on the issue.

## For glossval

The ranking experiment, two questions. Steps: where `next` offered
several, does a ranker put first the one the high-scoring sessions
took, against today's order? Relationship candidates: does it rank
the true ones above the coincidences, against today's ranking?
Untuned first. If it does not clearly beat the baselines, it is
dropped. First candidate: the contrastive language model
(https://github.com/Contrastive-LM/CLM), trained on glossval's log of
every call in every scored session. If it wins, it becomes a service
URL, `GLOSSDB_RANK_URL`, refused by name when unset.
