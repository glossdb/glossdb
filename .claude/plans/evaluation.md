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
| glossval's tools follow the server's renamed reads and the new `next`; the notes and tools of the old measurement are cut to what the contract test cases use | Medium: about 16,000 lines of tools read the old names | glossval `tools/`, its notes | Next | |
| The review step in the contract harness: a second agent answers the builder's assumptions from the reference's documentation (`tools/interact.py`) | Low | glossval `tools/contract_run.py` | With the first row | |
| Both test cases run three times each; cost, turns and scores per run | Low | glossval scenarios `ferc-steam`, `eia-generators` | After the first row | |
| The rows the builder misses on FERC (the new filing system: 3,909 of 5,221 found by hand) | Medium: PUDL's own mapping may not be reachable from the sources | glossval `ferc-steam` | With the runs | |
| The rejected lines of a CSV load are readable after the load, not only counted | Low | the extension's runner (`reject_errors` lives in the load's own connection) | After the first runs | |
| The running state on real loads: build on the first periods, then load the later ones one by one. Scored: does the table stay right, and does `next` name what changed | Low | both test cases | After the first runs | |
| The read stage: a second agent reads the built lake with DuckDB, `ducklake` and glossql and answers questions; against the same agent on the sources | Low | glossval | After the build stage | |
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
- **The harness** `tools/contract_run.py`: sources mounted, nothing
  loaded, the contract in the task, the built table exported and
  scored.
- **Measured so far.** By hand in plain SQL: EIA 99.0% of keys and
  95.7% of cells; FERC 96.8% of keys, 96.4% of cells, 86.4% of rows.
  One agent run on `ferc-steam`: 32 turns, 1.35 USD, 94.0% of keys,
  91.2% of cells, 0% of rows, because the reference writes plant
  names in lower case and the contract did not say so.

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

**glossval follows the renamed reads.** What it buys: the contract
test cases run against the current server, and the repository holds
only what they use. What is there: `tools/contract_run.py`,
`contract_score.py`, `gen_eia.py`, `gen_ferc.py`, `fetch_corpora.py`
and the two scenarios; the rename map of the server's reads. Done
when: a search for the old names in glossval finds nothing; both test
cases run end to end; the tools and notes no test case uses are
deleted.
