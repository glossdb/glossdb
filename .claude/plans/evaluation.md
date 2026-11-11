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
| A test case on typed sources: FERC Form 1's steam plant schedule from the old filing system and the new one, into PUDL's one cleaned table | Medium: PUDL also sorts free text into categories; the per-column score will show what a contract can ask for | glossval: a builder like `gen_eia.py`, a scenario, a contract | Next | |
| The harness runs a contract test case: sources mounted, nothing loaded, the contract in the task, the built table exported and scored; stops when `next` has no open row for the agent | Medium: `run.py` loads tables first and reads the old `next` columns | glossval `run.py`, `next_state.py` | After the first row | |
| The EIA test case with the CSV configuration: does an agent that follows the load skill reach the reference | Low | glossval `scenarios/eia-generators/` | With the harness | |
| The rejected lines of a CSV load are readable after the load, not only counted | Low | the extension's runner (`reject_errors` lives in the load's own connection) | After the first runs | |
| The running state on real loads: build on the first periods, then load the later ones one by one. Scored: does the table stay right, and does `next` name what changed | Low | both test cases, `next_state.py` | After the first runs | |
| The other tools that read the old `next` columns are adapted or deleted: `plan_lane.py`, `ab_seats.py`, `chat_agent.py`, `joint_report.py`, `score.py`, `truth_stack.py`, `truth_trial.py`, `mining/next_table.py`, `graph/graph.py` | Low | glossval | Before the pull requests | |
| The read stage: a second agent reads the built lake with DuckDB, `ducklake` and glossql and answers questions; against the same agent on the sources | Low | glossval `bare_run.py`, `bare/duck_mcp.py` | After the build stage | |
| Finance from `../glosstest`, labelled generated; one data set among others | Low | glossval | After the real data reports | |
| The existing test cases rerun, the Monday test, then the results page | Low | glossval, the websites | Last | |

Not planned: reading a CSV in place as a view; the same agent with
DuckDB only as a comparison (a story for the docs later).

## What is there

- **The CSV configuration.** `null_markers()` in the core kit is the
  list of strings an export writes for no value. The load skill and
  the loading page give the reader's options: `all_varchar`,
  `nullstr = null_markers()`, `store_rejects`. Walked over MCP on a
  five-line file: markers became NULL, a leading zero and a padded id
  were kept and trimmed, one broken line was dropped and counted.
- **The EIA test case** in glossval (`eia-generators`): nine monthly
  workbooks of EIA Form 860M as CSV, the table PUDL v2026.11.0
  publishes from them as the reference (338,246 rows, 33 columns), the
  contract from PUDL's descriptor. Built by `tools/gen_eia.py`.
- **The scorer** `tools/contract_score.py`: keys found, values equal
  per column, cells right, rows right in every column. The reference
  against itself scores 100%; a first pass by hand in plain SQL scores
  95.7% of cells. No agent has run on it.
- **FERC Form 1 in PUDL v2026.11.0**, checked on one schedule: the old
  system's table `f1_steam` (51,770 rows, 79 columns, short names),
  the new system's two tables (7,943 rows, long names), and PUDL's
  cleaned `core_ferc1__yearly_steam_plants_sched402` (34,984 rows, 39
  columns, 1994 to 2025). All three are Parquet. The cleaned table has
  other names, other units (MW, MWh), one utility id and fewer rows.

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

**A test case on typed sources: FERC Form 1 steam plants.** What it
buys: the main case of data middleware on real data, two systems of
record into one table, with a reference we did not write. What is
there: the three Parquet files of PUDL v2026.11.0 named above;
`tools/gen_eia.py` and `tools/contract_score.py` as the pattern. Done
when: `fetch_corpora.py ferc` builds the sources, the reference and
the contract; the scorer gives 100% for the reference against itself;
a first pass by hand is scored and the columns it cannot reach from
the sources are listed.
