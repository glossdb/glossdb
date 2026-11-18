# Sources plan

What can be loaded beyond CSV, Parquet and JSON: spreadsheets,
documents, and search over text. A source is what a load query
(`DECLARE RECIPE`) reads: files through DuckDB's readers, or a
service called through the extension's `glossql_service` (one table
in, one table out). Databases, dbt projects, semantic models and
lakes read in place are `platform.md`.

These wait for real data: a customer's workbook or handbook, or a
public set that is not synthetic. Building them is small. Testing
them without real data is the hard part, and it widens every suite.

| Element | Difficulty | What it touches | When | Issue |
|---|---|---|---|---|
| Spreadsheets: the values through DuckDB's `excel` extension; formulas, defined names and macro modules as rows through a separate reader | Easy for values; formulas need the reader | SPEC §3, `reader_functions()` in `crates/duck`, the image's extensions | When a customer brings a workbook | |
| Documents: a processing service the load query calls, text as passages keyed by document and reference | Easy | SPEC §3, one service through `glossql_service` | When a customer brings a handbook or a standard | |
| Search: `embed(text)` as a scalar service call, distance with DuckDB's `array_distance` | Easy | the extension's service call, one service | With documents | |
| Vector index: HNSW through DuckDB's `vss` extension | Easy to build | the image's extensions | When the full scan is too slow | |
| Ranking experiment | Easy, outside this repository | glossval | Beside the rest; blocks nothing | |

## What is there

- SPEC.md §3 names the source types: `relational_db | parquet | csv |
  json`. `grammar.ebnf` lists the same keys in a comment, so a new
  type is a spec change, and the corpus needs one real workbook or
  handbook first. A load query is DuckDB SQL over `read_csv`,
  `read_parquet` and `read_json` (`reader_functions()` in
  `crates/duck/src/lib.rs`).
- DuckDB's `excel` extension reads a sheet's values. A Rust reader
  for formulas, macro source, defined names and tables in xlsx, xlsm,
  xlsb, xls and ods exists (calamine). An open-source server reads
  PDF, Word and slides into structure, tables and reading order
  (docling); it runs per deployment, since the text is customer
  content.
- `glossql_service` calls a service from SQL with one table in and one
  out. No shipped kit calls it while the `outlook` kit is offloaded.
  The scalar form, one text in and one vector out, is new with
  `embed`.
- What each gives the layer. A workbook's formula becomes a metric
  definition whose basis names workbook, sheet and cell, checked
  against the value the workbook stored. A passage is cited by key
  from a definition or a convention (#220).
- Search ranks rows for a reader. A similarity is not a join key and
  not an identity, and it does not close a question. Identity is an
  explicit key.

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
