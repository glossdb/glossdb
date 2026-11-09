# The sources plan

What comes in: workbooks, documents, search, and the ranking
experiments. The shared frame, the terms, the gates and the
decisions are in `harness.md`. A source is what a recipe reads: a
reader the engine has over files, a database DuckDB attaches, or a
service called through the extension's `glossql_service`, one table in
and one table out, which stands; the scalar shape lands here with
`embed(text)`, its first user. It runs under the phase 1 gate.

## The table

| Element | Difficulty | What it touches | When | Issue |
|---|---|---|---|---|
| Spreadsheets as a source: the values through DuckDB's `excel` extension, the formulas, defined names and macro modules as rows through a reader the engine does not carry | Easy for the values; the formulas need a reader | SPEC §3, `reader_functions()` in `crates/duck`, the image's extensions | First | |
| Documents as a source, a processor service the recipe calls | Easy | SPEC §3, one service through `glossql_service` | After workbooks | |
| Search: `embed(text)` as a service scalar, distance in plain SQL (`array_distance`, the engine's own) | Easy | the extension's service seam, one service | After documents | |
| The relational source on the engine: a database DuckDB attaches (`postgres`, `sqlite`, `mysql`), or an Iceberg catalogue through DuckDB's `iceberg` extension, read-only, named by `location`, read by a recipe | Low: the extensions exist and the image carries `postgres` | SPEC §3's `via`, the facade's open, a suite case | When a customer names one | |
| Ranking and CLM experiments | Easy, outside the tree | nothing here; glossval | Beside it; blocks nothing | |
| Vector index | Medium | DuckDB's `vss` extension | When the full scan is too slow | |

## What stands

- The kinds: SPEC.md §3, `type: relational_db | parquet | csv | json`;
  `grammar.ebnf` lists the same keys in a comment, so a new kind is a
  spec change, not a production change. A recipe is DuckDB SQL over
  the readers the facade registers, `read_csv`, `read_parquet` and
  `read_json` (`reader_functions()` in `crates/duck/src/lib.rs`), and
  lands one table, typed by the recipe.
- A service is called from SQL through the extension's
  `glossql_service`: one table in, one table out, the URL and the bearer
  named once for the instance. The futures kit's forecast and estimate
  are its users; the scalar shape, one text in and one vector out,
  lands here.
- The quality rule that bounds search: identity is an explicit key,
  never text matching (`docs/quality/README.md`). Search ranks rows
  for a reader; a similarity is never a join key, an identity or what
  closes a question.

## Issues, drafted

In the repo's form: what it buys, what stands, done-when. Facts only.
When one is opened, its number goes into the table and the draft
leaves this file.

### Workbooks as a source

- **What it buys.** A company's workbook lands as tables, and its
  formulas, defined names, macro modules and queries land as rows.
  An agent reads a formula and writes the metric's grounding; the
  basis names workbook, sheet and cell. A migration is checked
  against the workbook's own stored values. A budget lands as the
  plan's table, and the driver formulas land as the definitions the
  propagation runs through. No calculation engine.
- **What stands.** SPEC.md §3 names four kinds. A recipe lands rows
  typed by the recipe; the rows are the interface. DuckDB's `excel`
  extension reads a sheet's values; a reader that reads formulas,
  macro source, defined names and tables from xlsx, xlsm, xlsb, xls
  and ods exists outside the engine (calamine). Pivot tables and
  Power Query are read by none of the candidates.
- **Done when.** The corpus holds one real workbook, and SPEC.md §3
  names the kind. A fixture workbook lands as tables and as
  definition rows keyed by path, sheet, and cell or name. A
  grounding's basis names a cell, and the grounding's result equals
  the workbook's stored value on the fixture. The suite holds it.

### Documents as a source, through a processor service

- **What it buys.** A handbook, a standard or a schema description
  lands as passages. An agent finds the passage it needs, writes a
  convention or a definition, and cites the passage by key. The
  critical data stays in the systems of record; documents give
  context.
- **What stands.** Same seams as the workbook: SPEC.md §3, the recipe
  as the landing, `glossql_service` as the call. A processor that reads
  PDF, Word and slides into structure, tables and reading order
  exists as an open server (docling) and runs per deployment, since
  text is customer content.
- **Done when.** The corpus holds one real handbook, and SPEC.md §3
  names the kind. A fixture document lands as passage rows: document,
  reference, ordinal, headings, kind, text, page; the key is document
  and reference. The same document processed twice, the second time
  with one paragraph added, keeps the untouched passages' references,
  or the issue records that a key of our own is needed. A gloss cites
  a passage by key and the suite holds it.

### Search: embed as a service scalar

- **What it buys.** An agent finds the passage it needs by meaning,
  not by string, over the passages a document landed.
- **What stands.** `array_distance` is the engine's own. The service
  call's table shape stands in the extension; the scalar shape is this
  issue's. The quality rule: identity never rides similarity
  (`docs/quality/README.md`).
- **Done when.** `embed(text)` is a scalar function the recipe names,
  answered by an embedder service the deployment names, refused by
  name when none is. The recipe lands the vector at unit length and
  the column records the model's name and revision. A query ordered
  by `array_distance` over a full scan returns the fixture passage in
  the top rows. 10,000 passages land with the embedder stopped
  half-way, and no half table results. The time per passage is
  recorded on the issue.

## For the other repos

- **glossval**: the ranking experiment. Question 1, steps: where the
  door offered several, does a picker rank first the one the
  high-scoring sessions took, against today's order. Question 2,
  candidates: on the relationship truth, does it rank the true edges
  above the coincidences, against today's ranking. Untuned first. If
  it does not clearly beat the baselines, it gets no place. It blocks
  nothing in either plan. The ranker to try first is the contrastive
  language model (https://github.com/Contrastive-LM/CLM): a frozen
  encoder with trained heads that scores candidates by dot product,
  one pass per new text; the training signal is glossval's record of
  every door call of every scored session. If it wins, it becomes a
  service point, `GLOSSDB_RANK_URL`, refused by name when unset, on
  the model service's GPU.
