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
| Both test cases run three times each, the server in the container; cost, turns and scores per run, before and after the review | Low | glossval scenarios `ferc-steam`, `eia-generators` | Next | |
| The running state on real loads: build on the first periods, then load the later ones one by one. Scored: does the table stay right, and does `next` name what changed | Medium: it is what the layer adds over a built table | both test cases | Next | |
| The read stage: a second agent reads the built lake with DuckDB, `ducklake` and glossql and answers questions; against the same agent on the sources | Medium | glossval | After the running state | |
| The plant name on FERC: the reference writes it in lower case, the contract and the reference's documentation say "as reported". The builder kept the filed case and asked; the review confirmed it from the documentation; every row is wrong in that column | Medium: rows right stays 0% on FERC until the contract states the case or the scorer ignores it | glossval `ferc-steam` (`tools/gen_ferc.py`, `contract.yaml`) or `tools/contract_score.py` | Before the runs are reported | |
| The rows the builder misses on FERC (the new filing system: 3,909 of 5,221 found by hand) | Medium: PUDL's own mapping may not be reachable from the sources | glossval `ferc-steam` | With the runs | |
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
- **Measured so far.** By hand in plain SQL: EIA 99.0% of keys and
  95.7% of cells; FERC 96.8% of keys, 96.4% of cells, 86.4% of rows.
  One agent run on `ferc-steam` in the container (sonnet): 28 turns,
  1.11 USD, 93.4% of keys, 90.6% of cells, 0% of rows. The builder
  left 10 assumptions open. The review confirmed 2, corrected none
  and left 8 open, because the documentation does not settle them.
  The scores before and after the review are the same.

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

**Both contract test cases, three runs each.** What it buys: the
first scores with their spread, on a server that cannot read the
reference. What is there: `tools/contract_run.py` runs a test case
with the server in the container; one `ferc-steam` run is measured
(above); `eia-generators` starts in the container and has not run
with a model. Done when: three runs of each test case are in
`evals/runs/`, each with `server: container` in `score.json`; a table
gives cost, turns, keys, cells and rows per run, before and after the
review; what the review confirmed, corrected and left open is counted
per run.
