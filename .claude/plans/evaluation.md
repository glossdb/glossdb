# Evaluation plan

glossval measures glossdb as data middleware: source data goes in, a
cleaned table in a given format comes out of the lake. An agent gets
the sources and a contract (table, key, columns, types, meanings, code
tables) and builds the table in glossdb. The score is a diff against a
reference that an independent party built.

Two cases, by what the source is:

- **Typed sources** (Parquet, database tables) are the main case.
  Nothing is cleaned at load. The work is views on top: one table from
  several systems that name and code the same things differently.
- **CSV** is the exception. The load gives DuckDB's CSV reader one
  standard configuration and casts in the load query.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| A change that empties a served column is not named. A view defined again with a broken expression took a column from 0 to 81% NULL (272,821 of 338,186 rows) and no test or `next` row said so; in the running state on FERC three later years were loaded and `next` showed 0 rows come and 0 gone | Medium: it is what the layer adds over a built table | the views kit (a column held against its state before a load or a new definition), `load_changes()`, `next` | Next | #243 |
| The running state on `eia-generators`; a third `erp-supply` run; the scorer's "handled" rule for a fault the builder removes at load (the second date format) | Low | glossval | With the row above | |
| The read stage: a second agent reads the built lake with DuckDB, `ducklake` and glossql and answers questions; against the same agent on the sources | Medium | glossval | After the running state | |
| The rejected lines of a CSV load are readable after the load, not only counted | Low | the extension's runner (`reject_errors` lives in the load's own connection) | After the first runs | |
| Finance from `../glosstest`, labelled generated; one data set among others | Low | glossval | After the real data reports | |
| The results page | Low | glossval, the websites | Last | |

Not planned: reading a CSV in place as a view; the same agent with
DuckDB only as a comparison (a story for the docs later).

## What is there

- **The CSV configuration.** `null_markers()` in the core kit is the
  list of strings an export writes for no value. The load skill gives
  the reader's options: `all_varchar`, `nullstr = null_markers()`,
  `store_rejects`, and casts over `trim()`.
- **Two test cases** in glossval, built by `tools/gen_eia.py` and
  `tools/gen_ferc.py` from PUDL v2026.11.0:
  - `eia-generators` (CSV): nine monthly workbooks of EIA Form 860M,
    the reference 338,246 rows and 33 columns.
  - `ferc-steam` (typed): FERC Form 1's steam plant schedule from the
    old filing system and the new one, the reference 34,984 rows and
    39 columns.
- **The scorer** `tools/contract_score.py`: keys found, values equal
  per column, cells right, rows right in every column. The reference
  against itself scores 100%.
- **The harness** `tools/contract_run.py`: nothing loaded, the
  contract in the task, the built table exported over HTTP and scored
  on the host. The review step is part of it: a second agent answers
  the builder's assumptions from the reference's documentation
  (`tools/interact.py`), and the builder applies the decisions.
- **The server of a run is a container** (`tools/harness.py`,
  `evals/container/`, Apple's `container`). The image holds the server
  and the extension at the last commits of the two checkouts. It
  mounts the run's workspace and the sources, read-only, and no other
  host path. Its network ends at the host. Measured by hand over MCP:
  a load from the sources works; a load query that names the
  reference's host path, `../reference` or the reference's web
  address fails. The same three load the reference when the server
  runs on the host (`--host`, for development; `score.json` records
  which). A server that confines a source's reads itself is a row of
  `gate.md`.
- **The tools follow the server.** glossval's tools read the
  server's renamed reads and the current `next`. The notes and tools
  of the old measurement are cut to what the contract test cases
  use.
- **Measured** at glossql `f3d2e14` and the extension `3fa3d78`, the
  server in the container, builder and reviewer on sonnet; the tables
  per run are in glossval's `evals/README.md`. `ferc-steam`, three
  runs: 93.2%, 93.7% and 97.3% of cells, 81.3% to 83.4% of rows, 1.11
  to 1.74 USD and 26 to 43 turns; one review correction took a run
  from 93.1% to 97.3% of cells. `eia-generators`, three runs: 99.0%
  of keys; 99.0%, 99.0% and 93.6% of cells; 98.7%, 98.7% and 18.9% of
  rows (the emptied column of the first row above); 1.59 to 2.02 USD.
  `erp-supply` (generated data), two runs: the blank global ids and
  the unmapped local codes found in both; five of ten fault classes
  have no test (#244). The running state on FERC, built on
  2021 and 2022, then three years loaded: 97.3% to 98.1% of cells so
  far, 83.3% to 85.6% on the new year alone. The goldens' baseline is
  accepted at these commits, every difference explained. 14.66 USD in
  all.

## What the scores are

- **Build.** Cells right, keys right, rows right in every column,
  against the reference. Cost and turns beside it.
- **Running.** After a later period is loaded: the same scores on the
  new period, and whether `next` named what changed.
- **Read.** Share of answers right on the built lake against the
  sources, same reader, same questions.

A result on generated data is labelled generated. The headline
numbers come from real data with a reference we did not write.

## Next issue (draft)

**A served column that empties is named.** What it buys: a load or a
new definition that takes a column of a served view from filled to
mostly NULL, or drops its rows, is a row in `next` with the column
and both shares. What is there: `column_profile` per column of a
table view, `load_changes()`, the two cases above in glossval's runs
(`eia-generators` 113746Z, the FERC running replay). Done when: on
both cases replayed, `next` names the column and the period.
